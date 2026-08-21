# ============================================================================
# tiles.R  -  On-demand tile rendering for the high-resolution viewer.
#
# The map is a slippy map in genomic-bp space (Leaflet Simple CRS, scale = 2^z).
# At integer zoom z, 1 pixel = 2^-z bp and one 256-px tile = 256 * 2^-z bp on a
# side. For each tile (z, x, y) we:
#   1. compute its genomic x- and y-ranges,
#   2. pick the .hic resolution closest to the tile's bp-per-pixel,
#   3. read ONLY that 2-D block with strawr,
#   4. nearest-neighbour sample it onto a 256x256 pixel grid aligned to the tile
#      box (so adjacent tiles line up exactly), and
#   5. colour it with a GLOBAL value scale (vmin/vmax) shared by all tiles.
#
# GENOME-WIDE MAPS
# ---------------
# `st$genome` (NULL for an ordinary map) switches both axes to the WHOLE
# genome: every chromosome laid end to end in one continuous bp coordinate,
# so all chromosome pairs - cis blocks down the diagonal, trans blocks off it -
# are visible at once. The coordinate a tile works in is then a GLOBAL bp
# position, and each pixel has to be turned back into (chromosome, local bp)
# before the file can be asked about it. A tile that straddles a boundary is
# therefore several reads, one per chromosome pair it touches.
#
# The genome axis is symmetric (the same chromosomes in the same order on both
# axes), so unlike a trans map it keeps a real diagonal - the split comparison
# view and its diagonal rule work here exactly as on a single chromosome.
#
# INTER-CHROMOSOME (TRANS) MAPS
# -----------------------------
# The two axes carry their own chromosome: `st$chrX`/`st$lenX` horizontally and
# `st$chrY`/`st$lenY` vertically. When they are the same chromosome (the usual
# case) the map is the familiar square cis map and `st$trans` is FALSE; when
# they differ the map is a rectangle showing the contacts BETWEEN two
# chromosomes, and everything that relies on the cis map's symmetry has to step
# aside:
#   * there is no diagonal, so the "split" comparison view - which puts sample A
#     above it and B below - is meaningless and falls back to a single sample,
#     as does the diagonal separator line;
#   * the matrix is not symmetric, so nothing is mirrored.
# The reads themselves are the same shape as before: one rectangular block per
# tile, rows = the Y chromosome's bins, columns = the X chromosome's.
#
# TWO-SAMPLE COMPARISON
# ---------------------
# A second .hic ("sample B") can be loaded alongside the first. `st$cmpMode`
# then selects how the two are combined into one map:
#   "single"  : sample A only (the default; also used when no B is loaded)
#   "split"   : upper-right triangle (genomic x > y) = A, lower-left = B.
#               Both halves share one resolution, one colour palette and one
#               value scale, so the two samples are directly comparable.
#   "curtain" : the browser stacks TWO tile layers (one per sample) and clips
#               them to opposite sides of a draggable divider, so the same
#               pixels can be compared. Nothing special happens here — each
#               layer just asks for its own sample via the `src` argument.
#   "diff"    : one value per pixel — log2((A+eps)/(B+eps)) or A-B — drawn on a
#               diverging palette centred on zero (see values_to_diff_colors).
# Because Hi-C maps are symmetric, the point (i,j) above the diagonal and (j,i)
# below it describe the SAME locus pair — which is what makes the split view a
# fair comparison.
#
# Sequencing-depth differences are corrected by multiplying B's values by
# `st$bfac` (computed once from the two overview matrices; see do_open_b()).
#
# VIRTUAL MULTI-RESOLUTION DATASET
# --------------------------------
# Several single-resolution .hic files (e.g. one ICE-normalized file per
# resolution) can be opened together as ONE dataset. `st$vmap` then maps each
# resolution (as a character key) to the file that serves it, and `st$vfac`
# maps each file path to a brightness factor that puts it on the reference
# (overview) file's value scale — the whole-chromosome sum ratio, computed
# once in do_open(). Sample A reads go through .vpath_a()/.vfac_a(); both are
# NULL for an ordinary single-file dataset, which keeps this a no-op.
#
# `st` is an environment holding: path, chrX, lenX, chrY, lenY, trans, res
# (available bp resolutions, ascending), norm, color, vmin, vmax, and a cached
# `blank` tile. For comparison it also holds: path2, norm2, bfac, cmpMode,
# cmpDiag; for a virtual dataset: vmap, vfac (see above).
# ============================================================================

TILE_PX <- 256L

choose_res <- function(bpp, res_asc) {
  res_asc[which.min(abs(log2(res_asc) - log2(bpp)))]
}

# ---- virtual multi-resolution dataset helpers (see header) -----------------
# which file serves sample A at this resolution
.vpath_a <- function(st, res) {
  vm <- st$vmap
  if (is.null(vm)) return(st$path)
  p <- vm[[as.character(res)]]
  if (is.null(p)) st$path else p
}
# brightness factor for that file (reference file = 1)
.vfac_a <- function(st, path) {
  f <- st$vfac
  if (is.null(f)) return(1)
  v <- f[[path]]
  if (is.null(v) || length(v) != 1 || !is.finite(v) || v <= 0) 1 else v
}

# ---- genome-wide coordinate system (see header) ---------------------------
# make_genome(): every chromosome laid end to end. `offset` holds each one's
# 0-based start in the global coordinate, so global bp = offset + local bp - 1.
# The aggregate pseudo-chromosome juicer writes (All / Assembly) is not a real
# chromosome and is dropped.
make_genome <- function(names, lengths) {
  nm <- as.character(names); ln <- suppressWarnings(as.numeric(lengths))
  keep <- !(tolower(nm) %in% c("all", "assembly")) & is.finite(ln) & ln > 0
  nm <- nm[keep]; ln <- ln[keep]
  if (!length(nm)) return(NULL)
  list(name = nm, length = ln,
       offset = c(0, cumsum(ln)[-length(ln)]), total = sum(ln))
}

# which chromosome each global bp position falls in (NA outside the genome)
gen_locate <- function(gen, g) {
  i <- findInterval(g, gen$offset)
  i[!is.finite(g) | g < 0 | g >= gen$total | i < 1] <- NA_integer_
  i
}

# global bp -> "chr:local bp", the only form worth showing a person
gen_label <- function(gen, g) {
  i <- gen_locate(gen, g)
  if (is.na(i)) return(list(chr = "", pos = NA_real_))
  list(chr = gen$name[i], pos = g - gen$offset[i] + 1)
}

# human-readable resolution label, e.g. 10000 -> "10 kb", 500 -> "500 bp"
fmt_res <- function(res) {
  if (is.null(res) || !is.finite(res)) return("")
  if (res >= 1000) paste0(res / 1000, " kb") else paste0(res, " bp")
}

blank_tile <- function(st) {
  if (!is.null(st$blank)) return(st$blank)
  f <- tempfile(fileext = ".png")
  png(f, width = TILE_PX, height = TILE_PX, bg = "transparent")
  # An empty page must still be DRAWN: R's cairo-based png device (Linux, and
  # macOS built against cairo) writes no file at all when nothing was plotted,
  # so the readBin() below would fail. plot.new() on a transparent background
  # produces exactly the same fully transparent tile, on every platform.
  par(mar = c(0, 0, 0, 0)); plot.new()
  dev.off()
  b <- readBin(f, "raw", n = file.info(f)$size); unlink(f)
  st$blank <- b; b
}

# ---------------------------------------------------------------------------
# .tile_values(): read ONE .hic and sample it onto this tile's 256x256 pixel
# grid. Returns a numeric matrix [row = y pixel, col = x pixel], or NULL when
# the tile falls outside the map or the read failed.
#
# The read is always rectangular: rows come from the Y axis's chromosome and
# columns from the X axis's, which for a cis map are the same chromosome and
# for a trans map are not. read_hic_map() takes its first chromosome as the
# ROW axis, so chrY goes in `chr` and chrX in `chr2`.
#
# Split out of render_tile() so the comparison modes can call it twice (once
# per sample) with exactly the same geometry and resolution.
# ---------------------------------------------------------------------------
.tile_values <- function(path, chrX, chrY, norm, res, lenX, lenY,
                         x0, x1, y0, y1, bpp) {
  if (is.null(path) || !nzchar(path)) return(NULL)
  xs <- max(1, floor(x0) + 1); xe <- min(lenX, ceiling(x1))
  ys <- max(1, floor(y0) + 1); ye <- min(lenY, ceiling(y1))
  if (xe <= xs || ye <= ys) return(NULL)

  m <- tryCatch(
    read_hic_map(path, chr = chrY, start = ys, end = ye,
                 resolution = res, normalization = norm,
                 chr2 = chrX, start2 = xs, end2 = xe),
    error = function(e) NULL)
  if (is.null(m) || is.null(dim(m)) || nrow(m) == 0 || ncol(m) == 0) return(NULL)

  locy <- parse_bin_labels(rownames(m))   # y bins (rows)
  locx <- parse_bin_labels(colnames(m))   # x bins (cols)

  px <- 0:(TILE_PX - 1)
  xc <- x0 + (px + 0.5) * bpp              # x-centre bp of each column pixel
  yc <- y0 + (px + 0.5) * bpp              # y-centre bp of each row pixel
  xidx <- findInterval(xc, locx$start)
  yidx <- findInterval(yc, locy$start)
  xidx[xc < 1 | xc > lenX | xidx < 1 | xidx > nrow(locx)] <- NA
  yidx[yc < 1 | yc > lenY | yidx < 1 | yidx > nrow(locy)] <- NA

  val <- matrix(NA_real_, TILE_PX, TILE_PX)  # [row = y pixel, col = x pixel]
  okr <- which(!is.na(yidx)); okc <- which(!is.na(xidx))
  if (length(okr) && length(okc)) val[okr, okc] <- m[yidx[okr], xidx[okc]]
  val
}

# ---------------------------------------------------------------------------
# .genome_fill(): the heart of the genome-wide view.
#
# Given the global bp position of every column (`xc`) and every row (`yc`) of a
# grid, fill that grid from the file. Each position is turned back into
# (chromosome, local bp); positions are grouped by chromosome, and every
# (column chromosome, row chromosome) pair the grid touches is read once and
# dropped into the cells that belong to it.
#
# Working from each cell's OWN position - rather than laying each chromosome's
# bins out end to end - is what keeps the grid exact: chromosome boundaries do
# not fall on bin boundaries, so stacking bins would leave a seam that is a
# cell too wide or too narrow at every boundary.
#
# Returns a matrix [row = y, col = x] of NA where nothing was read, or NULL if
# nothing at all could be read.
# ---------------------------------------------------------------------------
.genome_fill <- function(path, gen, norm, res, xc, yc) {
  if (is.null(path) || !nzchar(path) || is.null(gen)) return(NULL)
  xi <- gen_locate(gen, xc); yi <- gen_locate(gen, yc)
  if (!any(!is.na(xi)) || !any(!is.na(yi))) return(NULL)

  val <- matrix(NA_real_, length(yc), length(xc))
  got <- FALSE
  for (ci in unique(xi[!is.na(xi)])) {
    cols <- which(xi == ci)
    lx <- xc[cols] - gen$offset[ci]           # local bp on the column chromosome
    xs <- max(1, floor(min(lx)) + 1); xe <- min(gen$length[ci], ceiling(max(lx)))
    if (xe <= xs) next
    for (cj in unique(yi[!is.na(yi)])) {
      rows <- which(yi == cj)
      ly <- yc[rows] - gen$offset[cj]         # local bp on the row chromosome
      ys <- max(1, floor(min(ly)) + 1); ye <- min(gen$length[cj], ceiling(max(ly)))
      if (ye <= ys) next
      m <- tryCatch(
        read_hic_map(path, chr = gen$name[cj], start = ys, end = ye,
                     resolution = res, normalization = norm,
                     chr2 = gen$name[ci], start2 = xs, end2 = xe),
        error = function(e) NULL)
      if (is.null(m) || is.null(dim(m)) || !nrow(m) || !ncol(m)) next
      locy <- parse_bin_labels(rownames(m))
      locx <- parse_bin_labels(colnames(m))
      xidx <- findInterval(lx, locx$start)
      yidx <- findInterval(ly, locy$start)
      okc <- which(xidx >= 1 & xidx <= nrow(locx))
      okr <- which(yidx >= 1 & yidx <= nrow(locy))
      if (length(okc) && length(okr)) {
        val[rows[okr], cols[okc]] <- m[yidx[okr], xidx[okc]]
        got <- TRUE
      }
    }
  }
  if (got) val else NULL
}

# ---------------------------------------------------------------------------
# read_genome_map(): the whole genome as ONE matrix at `res`, for the overview
# that seeds the colour scale and answers the hover readout, and for the
# export, which needs the picture as a matrix rather than as tiles.
#
# Each cell is looked up at its own CENTRE, so no cell straddles a chromosome
# boundary. The last cell's centre can fall past the end of the genome (the
# genome is not a whole number of bins); it is pulled back inside so that the
# final sliver of the last chromosome is still drawn.
# ---------------------------------------------------------------------------
read_genome_map <- function(path, gen, res, norm = "NONE") {
  nb  <- ceiling(gen$total / res)
  ctr <- pmin((seq_len(nb) - 0.5) * res, gen$total - 1)
  m   <- .genome_fill(path, gen, norm, res, ctr, ctr)
  if (is.null(m)) return(matrix(0, nb, nb))
  m[is.na(m)] <- 0
  m
}

# ---------------------------------------------------------------------------
# .tile_values_genome(): one tile of a genome-wide map - the same fill, over
# the tile's 256 pixel centres.
# ---------------------------------------------------------------------------
.tile_values_genome <- function(path, gen, norm, res, x0, x1, y0, y1, bpp) {
  px <- 0:(TILE_PX - 1)
  .genome_fill(path, gen, norm, res,
               x0 + (px + 0.5) * bpp, y0 + (px + 0.5) * bpp)
}

# One reader for both worlds, so render_tile() does not have to branch at every
# call site: a genome-wide map goes through .tile_values_genome(), anything
# else through .tile_values().
.tile_read <- function(st, path, norm, res, x0, x1, y0, y1, bpp) {
  if (!is.null(st$genome))
    .tile_values_genome(path, st$genome, norm, res, x0, x1, y0, y1, bpp)
  else
    .tile_values(path, st$chrX, st$chrY, norm, res,
                 st$lenX, st$lenY, x0, x1, y0, y1, bpp)
}

# Encode a 256x256 colour vector (column-major, matching the value matrix) as a
# PNG tile.
.tile_png <- function(cols) {
  ras <- grDevices::as.raster(matrix(cols, TILE_PX, TILE_PX))
  f <- tempfile(fileext = ".png")
  png(f, width = TILE_PX, height = TILE_PX, bg = "transparent")
  par(mar = c(0, 0, 0, 0)); plot.new()
  plot.window(c(0, 1), c(0, 1), xaxs = "i", yaxs = "i")
  rasterImage(ras, 0, 0, 1, 1, interpolate = FALSE)
  dev.off()
  b <- readBin(f, "raw", n = file.info(f)$size); unlink(f); b
}

# render_tile(st, z, x, y, src)
#   src = "a" : sample A, or the merged split view when st$cmpMode == "split"
#   src = "b" : sample B alone, depth-corrected onto A's scale. Requested by the
#               curtain view's second tile layer.
render_tile <- function(st, z, x, y, src = "a") {
  # non-negative zoom: z in 0..maxZoom; at z=maxZoom, 1 pixel = baseRes bp
  bpp     <- st$baseRes * 2^(st$maxZoom - z)   # bp per pixel at this zoom
  bppTile <- TILE_PX * bpp                      # bp spanned by one tile
  x0 <- x * bppTile; x1 <- x0 + bppTile
  y0 <- y * bppTile; y1 <- y0 + bppTile
  # each axis is clipped to its OWN chromosome: on a trans map the two lengths
  # differ, so the drawn area is a rectangle rather than a square. A genome-wide
  # map uses the whole genome's length on both.
  if (x0 >= st$lenX || y0 >= st$lenY || x1 <= 0 || y1 <= 0)
    return(blank_tile(st))

  # resolution: auto (matched to the tile's bp-per-pixel) or a user-fixed value
  # that stays constant regardless of the view area. Snap the fixed value to an
  # available resolution for safety. With a comparison sample loaded, st$res is
  # the INTERSECTION of both files' resolutions, so A and B are always read at
  # the same bin size and their counts stay comparable.
  res <- if (isTRUE(st$autoRes) || is.null(st$fixedRes)) {
    choose_res(bpp, st$res)
  } else {
    st$res[which.min(abs(st$res - st$fixedRes))]
  }

  # A genome-wide tile reads every chromosome pair it touches, so a resolution
  # pinned far finer than the tile can show would ask for the whole genome at
  # that bin size - gigabytes, for a 256-px picture. Allow 4x oversampling and
  # no more: past that the extra bins cannot be seen anyway. A single-
  # chromosome map reads one block and needs no such guard.
  if (!is.null(st$genome)) {
    maxBins <- TILE_PX * 4
    # measure the part of the tile that is actually inside the genome - an edge
    # tile hangs over the end and would otherwise look far more expensive than
    # it is
    span <- max(min(x1, st$lenX) - max(x0, 0), min(y1, st$lenY) - max(y0, 0))
    if (is.finite(span) && span / res > maxBins) {
      fits <- st$res[span / st$res <= maxBins]
      res  <- if (length(fits)) min(fits) else max(st$res)
    }
  }

  mode <- if (is.null(st$path2) || !nzchar(st$path2)) "single"
          else if (is.null(st$cmpMode)) "single" else st$cmpMode
  # The split view divides the map along the diagonal, which only exists on a
  # cis map. The UI does not offer it for a trans map; this is the backstop for
  # a mode left over from a previous cis view.
  if (identical(mode, "split") && isTRUE(st$trans)) mode <- "single"

  # sample A's file and brightness factor at this resolution (virtual
  # datasets read a different file per resolution; single files pass through)
  pA <- .vpath_a(st, res)
  fA <- .vfac_a(st, pA)

  # depth correction: put B on A's count scale
  bfac <- st$bfac
  if (is.null(bfac) || length(bfac) != 1 || !is.finite(bfac) || bfac <= 0) bfac <- 1

  if (identical(src, "b")) {
    # sample B on its own (curtain view). Same geometry, same resolution and the
    # same global colour scale as the A layer, so the two line up pixel for pixel.
    if (identical(mode, "single")) return(blank_tile(st))
    val <- .tile_read(st, st$path2, st$norm2, res, x0, x1, y0, y1, bpp)
    if (is.null(val)) return(blank_tile(st))
    val <- val * bfac
  } else if (identical(mode, "diff")) {
    # ---- difference map ---------------------------------------------------
    # Both samples are read for the whole tile and reduced to ONE signed value
    # per pixel, drawn on a diverging palette centred on zero.
    #
    #   log2 : log2((A + eps) / (B + eps))  - fold change. The pseudo-count eps
    #          keeps sparse bins (where a 0 vs 1 count would give +/-Inf) from
    #          dominating the picture. A ratio is dimensionless, so its scale
    #          limit needs no resolution correction - but eps is in count units
    #          and therefore does.
    #   sub  : A - B                        - absolute change. This IS in count
    #          units, so both it and its limit scale with bin area.
    vA <- .tile_read(st, pA, st$norm, res, x0, x1, y0, y1, bpp)
    vB <- .tile_read(st, st$path2, st$norm2, res, x0, x1, y0, y1, bpp)
    if (is.null(vA) || is.null(vB)) return(blank_tile(st))
    vA <- vA * fA
    vB <- vB * bfac

    f   <- (res / st$ovres)^2
    lim <- st$diffLim
    if (is.null(lim) || length(lim) != 1 || !is.finite(lim) || lim <= 0) lim <- 1
    if (identical(st$diffType, "sub")) {
      d   <- vA - vB
      lim <- lim * f
    } else {
      eps <- st$diffEps
      if (is.null(eps) || length(eps) != 1 || !is.finite(eps) || eps <= 0) eps <- 1
      eps <- eps * f
      d   <- log2((vA + eps) / (vB + eps))
    }
    dcol <- st$diffColor
    if (is.null(dcol) || !nzchar(dcol)) dcol <- "bwr"
    return(.tile_png(values_to_diff_colors(as.vector(d), dcol, lim)))

  } else if (identical(mode, "split")) {
    # Which half of the diagonal does this tile touch?
    #   upper-right (genomic x > y) = sample A   -> exists when x1 > y0
    #   lower-left  (genomic x < y) = sample B   -> exists when y1 > x0
    needA <- x1 > y0
    needB <- y1 > x0
    vA <- if (needA) .tile_read(st, pA, st$norm, res, x0, x1, y0, y1, bpp) else NULL
    vB <- if (needB) .tile_read(st, st$path2, st$norm2, res, x0, x1, y0, y1, bpp) else NULL
    if (is.null(vA) && is.null(vB)) return(blank_tile(st))
    if (!is.null(vA)) vA <- vA * fA
    if (!is.null(vB)) vB <- vB * bfac

    px <- 0:(TILE_PX - 1)
    xc <- x0 + (px + 0.5) * bpp
    yc <- y0 + (px + 0.5) * bpp
    # upper[i, j] is TRUE where the pixel's genomic x >= y (the A half). Rows are
    # y pixels and columns are x pixels, matching .tile_values()'s orientation.
    upper <- outer(yc, xc, function(yy, xx) xx >= yy)

    val <- matrix(NA_real_, TILE_PX, TILE_PX)
    if (!is.null(vA)) val[upper]  <- vA[upper]
    if (!is.null(vB)) val[!upper] <- vB[!upper]
  } else {
    val <- .tile_read(st, pA, st$norm, res, x0, x1, y0, y1, bpp)
    if (is.null(val)) return(blank_tile(st))
    val <- val * fA
  }

  # Contact counts scale ~ resolution^2 (a coarse bin sums finer bins), so scale
  # the global vmin/vmax to this tile's resolution to keep colours consistent
  # across zoom levels in multi-resolution files. Guard against a transient
  # missing/invalid vmax so a redraw never blanks the whole map.
  vmn <- st$vmin; if (is.null(vmn) || length(vmn) != 1 || !is.finite(vmn)) vmn <- 0
  vmx <- st$vmax; if (is.null(vmx) || length(vmx) != 1 || !is.finite(vmx) || vmx <= vmn)
    vmx <- suppressWarnings(max(val, na.rm = TRUE))
  if (!is.finite(vmx)) vmx <- vmn + 1
  f <- (res / st$ovres)^2
  cols <- values_to_colors(as.vector(val), st$color, vmn * f, vmx * f)

  # thin separator along the diagonal so the two halves are unmistakable
  if (identical(mode, "split") && isTRUE(st$cmpDiag)) {
    px <- 0:(TILE_PX - 1)
    xc <- x0 + (px + 0.5) * bpp
    yc <- y0 + (px + 0.5) * bpp
    d <- outer(yc, xc, function(yy, xx) abs(xx - yy) < bpp)
    if (any(d)) cols[which(d)] <- "#606060"
  }

  # Chromosome boundaries. Without them a genome-wide map is an unreadable
  # field of blocks, so every chromosome start gets a hairline on both axes.
  # A pixel is on the line when a boundary falls inside the pixel's own bp
  # width, which keeps the rules exactly one pixel wide at every zoom.
  if (!is.null(st$genome) && !isTRUE(st$noGrid)) {
    b  <- st$genome$offset[-1]                      # the internal boundaries
    px <- 0:(TILE_PX - 1)
    xc <- x0 + (px + 0.5) * bpp
    yc <- y0 + (px + 0.5) * bpp
    onx <- vapply(xc, function(v) any(abs(b - v) <= bpp / 2), logical(1))
    ony <- vapply(yc, function(v) any(abs(b - v) <= bpp / 2), logical(1))
    m <- matrix(FALSE, TILE_PX, TILE_PX)            # [row = y, col = x]
    if (any(onx)) m[, which(onx)] <- TRUE
    if (any(ony)) m[which(ony), ] <- TRUE
    if (any(m)) cols[which(m)] <- "#7a7a7a"
  }

  .tile_png(cols)
}
