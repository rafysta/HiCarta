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
# `st` is an environment holding: path, chr, chrlen, res (available bp
# resolutions, ascending), norm, color, vmin, vmax, and a cached `blank` tile.
# For comparison it also holds: path2, norm2, bfac, cmpMode, cmpDiag.
# ============================================================================

TILE_PX <- 256L

choose_res <- function(bpp, res_asc) {
  res_asc[which.min(abs(log2(res_asc) - log2(bpp)))]
}

# human-readable resolution label, e.g. 10000 -> "10 kb", 500 -> "500 bp"
fmt_res <- function(res) {
  if (is.null(res) || !is.finite(res)) return("")
  if (res >= 1000) paste0(res / 1000, " kb") else paste0(res, " bp")
}

blank_tile <- function(st) {
  if (!is.null(st$blank)) return(st$blank)
  f <- tempfile(fileext = ".png")
  png(f, width = TILE_PX, height = TILE_PX, bg = "transparent"); dev.off()
  b <- readBin(f, "raw", n = file.info(f)$size); unlink(f)
  st$blank <- b; b
}

# ---------------------------------------------------------------------------
# .tile_values(): read ONE .hic and sample it onto this tile's 256x256 pixel
# grid. Returns a numeric matrix [row = y pixel, col = x pixel], or NULL when
# the tile falls outside the chromosome or the read failed.
#
# Split out of render_tile() so the comparison modes can call it twice (once
# per sample) with exactly the same geometry and resolution.
# ---------------------------------------------------------------------------
.tile_values <- function(path, chr, norm, res, chrlen, x0, x1, y0, y1, bpp) {
  if (is.null(path) || !nzchar(path)) return(NULL)
  xs <- max(1, floor(x0) + 1); xe <- min(chrlen, ceiling(x1))
  ys <- max(1, floor(y0) + 1); ye <- min(chrlen, ceiling(y1))
  if (xe <= xs || ye <= ys) return(NULL)

  m <- tryCatch(
    read_hic_map(path, chr = chr, start = ys, end = ye,
                 resolution = res, normalization = norm,
                 chr2 = chr, start2 = xs, end2 = xe),
    error = function(e) NULL)
  if (is.null(m) || is.null(dim(m)) || nrow(m) == 0 || ncol(m) == 0) return(NULL)

  locy <- parse_bin_labels(rownames(m))   # y bins (rows)
  locx <- parse_bin_labels(colnames(m))   # x bins (cols)

  px <- 0:(TILE_PX - 1)
  xc <- x0 + (px + 0.5) * bpp              # x-centre bp of each column pixel
  yc <- y0 + (px + 0.5) * bpp              # y-centre bp of each row pixel
  xidx <- findInterval(xc, locx$start)
  yidx <- findInterval(yc, locy$start)
  xidx[xc < 1 | xc > chrlen | xidx < 1 | xidx > nrow(locx)] <- NA
  yidx[yc < 1 | yc > chrlen | yidx < 1 | yidx > nrow(locy)] <- NA

  val <- matrix(NA_real_, TILE_PX, TILE_PX)  # [row = y pixel, col = x pixel]
  okr <- which(!is.na(yidx)); okc <- which(!is.na(xidx))
  if (length(okr) && length(okc)) val[okr, okc] <- m[yidx[okr], xidx[okc]]
  val
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
  if (x0 >= st$chrlen || y0 >= st$chrlen || x1 <= 0 || y1 <= 0)
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

  mode <- if (is.null(st$path2) || !nzchar(st$path2)) "single"
          else if (is.null(st$cmpMode)) "single" else st$cmpMode

  # depth correction: put B on A's count scale
  bfac <- st$bfac
  if (is.null(bfac) || length(bfac) != 1 || !is.finite(bfac) || bfac <= 0) bfac <- 1

  if (identical(src, "b")) {
    # sample B on its own (curtain view). Same geometry, same resolution and the
    # same global colour scale as the A layer, so the two line up pixel for pixel.
    if (identical(mode, "single")) return(blank_tile(st))
    val <- .tile_values(st$path2, st$chr, st$norm2, res,
                        st$chrlen, x0, x1, y0, y1, bpp)
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
    vA <- .tile_values(st$path,  st$chr, st$norm,  res,
                       st$chrlen, x0, x1, y0, y1, bpp)
    vB <- .tile_values(st$path2, st$chr, st$norm2, res,
                       st$chrlen, x0, x1, y0, y1, bpp)
    if (is.null(vA) || is.null(vB)) return(blank_tile(st))
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
    vA <- if (needA) .tile_values(st$path,  st$chr, st$norm,  res,
                                  st$chrlen, x0, x1, y0, y1, bpp) else NULL
    vB <- if (needB) .tile_values(st$path2, st$chr, st$norm2, res,
                                  st$chrlen, x0, x1, y0, y1, bpp) else NULL
    if (is.null(vA) && is.null(vB)) return(blank_tile(st))
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
    val <- .tile_values(st$path, st$chr, st$norm, res,
                        st$chrlen, x0, x1, y0, y1, bpp)
    if (is.null(val)) return(blank_tile(st))
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

  .tile_png(cols)
}
