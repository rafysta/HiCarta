# ============================================================================
# export.R  -  Publication / print export of a Hi-C contact map.
#
# Renders a chosen region to the current graphics device, then to a PNG or PDF
# file at a requested paper size, or straight to the default printer. It reuses
# the interactive view's global colour scale (vmin/vmax, palette) so the exported
# image matches what is on screen.
#
# Each axis carries its own chromosome and range: `chr`/`start`/`end` for the
# horizontal one and `chr_y`/`ystart`/`yend` for the vertical. They default to
# each other, which is the ordinary square cis map; giving the vertical axis a
# different chromosome exports the inter-chromosome (trans) map between the two.
#
# Public functions
#   read_export_matrix(st, chr, start, end, ...) -> list(m, res, split, diff)
#   draw_export_map(m, chr, start, end, ...)     -> draws to current device
#   write_export_file(file, fmt, width_mm, height_mm, dpi, draw_fn)
#   print_file(pdf)                              -> send a PDF to the default printer
#
# `st` is the tile-render state environment from app.R (path, chrX, lenX, chrY,
# lenY, trans, res, norm, color, vmin, vmax, ovres).
# ============================================================================

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Largest number of bins the exported matrix may span on its longer axis.
EXPORT_MAX_BINS <- 4000

# Format a bp value as a short axis label (Mb / kb / bp).
fmt_bp <- function(v) {
  vapply(v, function(x) {
    ax <- abs(x)
    if (ax >= 1e6)      paste0(format(round(x / 1e6, 2), trim = TRUE, nsmall = 0), " Mb")
    else if (ax >= 1e3) paste0(format(round(x / 1e3, 1), trim = TRUE, nsmall = 0), " kb")
    else                as.character(round(x))
  }, character(1))
}

# Read a region matrix for export.
#
# `resolution` pins the bin size - pass the one the map on screen is drawing
# with and the exported picture is built from exactly the same bins, so it
# matches what the user is looking at (this is the default; it also carries a
# pinned resolution over from the Display panel). Without it, a resolution is
# picked so the region spans ~target_bins bins. Either way the read is capped
# at 4000 bins on the longer axis, so a fine resolution over a whole
# chromosome cannot produce an unusable matrix; `res` in the returned list is
# always the resolution actually used.
#
# With a comparison sample attached and st$cmpMode == "split", the two samples
# are merged exactly as on screen: the upper-right triangle (column >= row, i.e.
# genomic x >= y) comes from A and the lower-left from B, with B multiplied by
# st$bfac to match A's sequencing depth. The returned `split` flag lets the
# caller know it should also draw the diagonal / corner labels.
read_export_matrix <- function(st, chr, start, end, target_bins = 1500,
                               chr_y = chr, ystart = start, yend = end,
                               resolution = NULL) {
  start  <- max(1, as.numeric(start));  end  <- as.numeric(end)
  ystart <- max(1, as.numeric(ystart)); yend <- as.numeric(yend)
  # The resolution is picked from the LONGER axis, so a tall thin (or short
  # wide) trans region still comes back as a matrix of a workable size.
  span  <- max(1, end - start + 1, yend - ystart + 1)
  res   <- if (!is.null(resolution) && length(resolution) == 1 &&
               is.finite(resolution) && resolution > 0)
             st$res[which.min(abs(st$res - resolution))]   # snap to an available one
           else
             choose_res(span / target_bins, st$res)
  # Keep the matrix tractable. Unlike the screen, which reads one small block
  # per 256-px tile, the export reads the whole region at once, so a fine
  # resolution over a whole chromosome would allocate a huge matrix. Fall back
  # to the FINEST resolution that still fits the cap - picking the nearest one
  # to a target, as this used to, can land on a resolution that busts the cap
  # again (for a 4.5 Mb chromosome, `nearest to span/2000` is 1 kb, which is
  # exactly the resolution being rejected).
  if (span / res > EXPORT_MAX_BINS) {
    ok  <- st$res[span / st$res <= EXPORT_MAX_BINS]
    res <- if (length(ok)) min(ok) else max(st$res)
  }
  # virtual multi-resolution dataset: this resolution's file + its brightness
  # factor (see tiles.R); ordinary single files pass straight through
  pA <- .vpath_a(st, res)
  # rows = the vertical axis, columns = the horizontal one. A genome-wide map
  # is assembled from every chromosome pair instead of read as one block.
  gen <- st$genome
  rd <- function(p, nrm) {
    if (!is.null(gen)) read_genome_map(p, gen, res, nrm)
    else read_hic_map(p, chr = chr_y, start = ystart, end = yend,
                      resolution = res, normalization = nrm,
                      chr2 = chr, start2 = start, end2 = end)
  }
  m <- rd(pA, st$norm)
  m <- m * .vfac_a(st, pA)

  has_b <- !is.null(st$path2) && nzchar(st$path2)
  # the split view divides the map along a diagonal that a trans map does not
  # have (see tiles.R), so it is never used for one
  split <- identical(st$cmpMode, "split") && has_b &&
           (!is.null(st$genome) || (identical(chr, chr_y) && !isTRUE(st$trans)))
  diff  <- identical(st$cmpMode, "diff")  && has_b
  if (split || diff) {
    mb <- tryCatch(rd(st$path2, st$norm2), error = function(e) NULL)
    if (is.null(mb) || !identical(dim(mb), dim(m))) {
      split <- FALSE; diff <- FALSE
    } else {
      bf <- st$bfac
      if (is.null(bf) || length(bf) != 1 || !is.finite(bf) || bf <= 0) bf <- 1
      mb <- mb * bf
      if (diff) {
        # same arithmetic as render_tile(), so the printed figure matches the
        # screen exactly (eps and the count-difference limit both scale with
        # bin area; a log2 ratio is dimensionless and does not)
        f <- (res / (st$ovres %||% res))^2
        if (identical(st$diffType, "sub")) {
          m <- m - mb
        } else {
          eps <- st$diffEps
          if (is.null(eps) || length(eps) != 1 || !is.finite(eps) || eps <= 0) eps <- 1
          m <- log2((m + eps * f) / (mb + eps * f))
        }
      } else {
        # rows = y bins, columns = x bins (same bins on both axes), so the
        # upper-right half of the picture is column index >= row index.
        lower <- outer(seq_len(nrow(m)), seq_len(ncol(m)), function(i, j) j < i)
        m[lower] <- mb[lower]
      }
    }
  }
  list(m = m, res = res, split = split, diff = diff)
}

# Draw the contact map (and, optionally, 1-D tracks below it) to the CURRENT
# device.
#   ticks      : draw coordinate axes/ticks (座標メモリ)
#   legend     : draw a colour-scale bar (凡例)
#   no_margin  : fill the whole canvas edge-to-edge (余白を空けない) - map only,
#                overrides ticks/legend/tracks.
#   tracks     : list of list(height = <px>, draw = function(mar) ...). Each is
#                stacked below the map, sharing the map's x-range and left/right
#                margins so columns line up. `draw` receives the margin to use.
#   map_weight : relative height of the map row vs. track heights (use the
#                on-screen contact-map height so proportions match the app).
#   m          : the contact matrix, or NULL to export the tracks alone (no
#                contact map loaded) - a coordinate axis is drawn instead.
#   diagonal   : draw a thin line along the diagonal (two-sample split view)
#   label_a/b  : captions for the upper-right / lower-left halves (split view).
#                A printed figure travels on its own, so which sample is where
#                must be readable from the image itself.
#   diff       : the matrix holds SIGNED differences - colour it with the
#                diverging palette on the symmetric range [vmin, vmax] (which the
#                caller sets to -lim / +lim) instead of the sequential one.
#   genome     : the genome table (name/length/offset/total) when both axes are
#                the whole genome. The axes are then labelled with chromosome
#                NAMES and ruled at the boundaries - a running bp total across
#                every chromosome would tell a reader nothing.
#   equal_scale: give both axes the same number of bp per mm on paper, so a
#                given distance means the same thing horizontally and
#                vertically. Without it the map is stretched to fill whatever
#                space the paper size leaves it, which distorts a region whose
#                two axes span different numbers of bp - the normal case for an
#                inter-chromosome map. With tracks below the map the map row is
#                also given the height that equal scaling asks for, so the map
#                still fills the width and the tracks stay aligned with it;
#                when that height will not fit on the page the map is centred
#                in the row it has instead.
draw_export_map <- function(m, chr, start, end,
                            color = "matlab", vmin = 0, vmax = 1,
                            ticks = TRUE, legend = TRUE, no_margin = FALSE,
                            tracks = list(), map_weight = 720,
                            diagonal = FALSE, label_a = NULL, label_b = NULL,
                            diff = FALSE,
                            chr_y = chr, ystart = start, yend = end,
                            equal_scale = FALSE, genome = NULL) {
  start  <- max(1, as.numeric(start));  end  <- as.numeric(end)
  # the vertical axis defaults to the horizontal one (a square cis map)
  ystart <- max(1, as.numeric(ystart)); yend <- as.numeric(yend)
  if (!is.finite(ystart) || !is.finite(yend) || yend <= ystart) {
    ystart <- start; yend <- end
  }
  # plot.window() takes NA to mean "no aspect constraint", which is its default
  asp_v <- if (isTRUE(equal_scale)) 1 else NA_real_
  xspan <- end - start; yspan <- yend - ystart

  # Chromosome names centred on each chromosome, and a hairline at every
  # boundary, on whichever axis is asked for. Only drawn for a genome-wide map.
  .genome_axis <- function(side) {
    if (is.null(genome)) return(invisible())
    horiz <- side == 3
    mid <- genome$offset + genome$length / 2
    graphics::axis(side, at = mid, labels = genome$name, tick = FALSE,
                   las = if (horiz) 1 else 1, mgp = c(3, if (horiz) 0.3 else 0.5, 0),
                   cex.axis = 0.8)
    bnd <- genome$offset[-1]
    if (length(bnd))
      graphics::axis(side, at = bnd, labels = FALSE, tcl = -0.3,
                     lwd = 0, lwd.ticks = 1)
    invisible()
  }
  # the same boundaries drawn ACROSS the map, so the blocks are readable.
  # segments() rather than abline(): under equal scaling the plot region is
  # larger than the map, and a full-width rule would run out into the padding.
  .genome_grid <- function() {
    if (is.null(genome)) return(invisible())
    bnd <- genome$offset[-1]
    if (!length(bnd)) return(invisible())
    vb <- bnd[bnd > start  & bnd < end]
    hb <- bnd[bnd > ystart & bnd < yend]
    if (length(vb)) graphics::segments(vb, ystart, vb, yend, col = "#7a7a7a", lwd = 0.5)
    if (length(hb)) graphics::segments(start, hb, end, hb, col = "#7a7a7a", lwd = 0.5)
    invisible()
  }

  # Corner captions + diagonal rule for the split (two-sample) view. Uses
  # legend() rather than text() because it anchors to the plot-region corners
  # regardless of the reversed y-axis.
  .split_marks <- function(cex = 0.8) {
    if (isTRUE(diagonal))
      graphics::segments(start, start, end, end, col = "#606060", lwd = 0.8)
    if (!is.null(label_a) && nzchar(label_a))
      graphics::legend("topright", legend = label_a, bty = "o", cex = cex,
                       bg = "#FFFFFFCC", box.col = "#BBBBBB", box.lwd = 0.6,
                       x.intersp = 0, y.intersp = 0.9, adj = 0)
    if (!is.null(label_b) && nzchar(label_b))
      graphics::legend("bottomleft", legend = label_b, bty = "o", cex = cex,
                       bg = "#FFFFFFCC", box.col = "#BBBBBB", box.lwd = 0.6,
                       x.intersp = 0, y.intersp = 0.9, adj = 0)
    invisible()
  }

  # ---- tracks only (no contact map): a coordinate axis + stacked tracks -----
  if (is.null(m)) {
    ntr <- length(tracks)
    if (ntr == 0) { graphics::plot.new(); return(invisible()) }
    LEFT  <- if (isTRUE(ticks)) 4.8 else 0.3
    RIGHT <- 1
    axis_h    <- if (isTRUE(ticks)) 60 else 1     # thin row holding the x-axis
    track_mar <- c(0.3, LEFT, 0.3, RIGHT)
    hts <- c(axis_h, vapply(tracks, function(t) as.numeric(t$height), numeric(1)))
    graphics::layout(matrix(seq_len(ntr + 1L), ncol = 1), heights = hts)
    op <- graphics::par(mar = c(0.2, LEFT, 3.6, RIGHT)); on.exit(graphics::par(op))
    graphics::plot.new()
    graphics::plot.window(xlim = c(start, end), ylim = c(0, 1), xaxs = "i", yaxs = "i")
    if (isTRUE(ticks)) {
      tk <- pretty(c(start, end), n = 6); tk <- tk[tk >= start & tk <= end]
      graphics::axis(3, at = tk, labels = fmt_bp(tk), tcl = -0.4, mgp = c(3, 0.5, 0))
      graphics::mtext(chr, side = 3, line = 2.3, cex = 1.0)
    }
    for (t in tracks) {
      dfn <- t$draw
      if (is.function(dfn)) tryCatch(dfn(track_mar), error = function(e) {
        graphics::par(mar = track_mar); graphics::plot.new()
      })
    }
    return(invisible())
  }

  cols  <- if (isTRUE(diff))
             values_to_diff_colors(as.vector(m), color, max(abs(c(vmin, vmax))))
           else
             values_to_colors(as.vector(m), color, vmin, vmax)
  cols[is.na(as.vector(m))] <- "#FFFFFF"                    # opaque white where no data
  ras   <- grDevices::as.raster(matrix(cols, nrow(m), ncol(m)))

  # --- no margin: fill the canvas with just the map ------------------------
  if (isTRUE(no_margin)) {
    op <- graphics::par(mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 0))
    on.exit(graphics::par(op))
    graphics::plot.new()
    graphics::plot.window(xlim = c(start, end), ylim = c(yend, ystart),
                          xaxs = "i", yaxs = "i", asp = asp_v)
    graphics::rasterImage(ras, start, yend, end, ystart, interpolate = FALSE)
    .genome_grid()
    .split_marks()
    return(invisible())
  }

  ntr   <- length(tracks)
  LEFT  <- if (isTRUE(ticks)) 4.8 else 0.3    # room for the map's y-axis labels
  RIGHT <- 1
  TOP   <- if (isTRUE(ticks)) 3.6 else 1      # room for the map's x-axis (on TOP)
  # shared column margins keep the map body and every track x-aligned
  body_mar  <- c(if (ntr > 0) 0.3 else 0.6, LEFT, TOP, RIGHT)
  track_mar <- c(0.3, LEFT, 0.3, RIGHT)

  # How tall the map body has to be for equal scaling, in inches. Only needed
  # when tracks are stacked below it: they are drawn to the map's x-axis, so the
  # map has to keep the full cell width, and the only way to also get the bp
  # scale right is to make its ROW the right height. par("din") is the device
  # size and par("csi") one line of margin, both in inches.
  .equal_row_in <- function() {
    if (!isTRUE(equal_scale) || !is.finite(xspan) || xspan <= 0) return(NA_real_)
    din <- graphics::par("din"); csi <- graphics::par("csi")
    wfrac  <- if (isTRUE(legend)) 6 / 7 else 1         # the legend column's share
    body_w <- din[1] * wfrac - (LEFT + RIGHT) * csi    # map body width, inches
    if (!is.finite(body_w) || body_w <= 0) return(NA_real_)
    h <- body_w * (yspan / xspan) + (body_mar[1] + body_mar[3]) * csi
    if (!is.finite(h) || h <= 0.2) NA_real_ else h
  }

  # ---- figure layout: map row on top, one row per track, optional legend col.
  if (ntr > 0) {
    hts <- c(as.numeric(map_weight), vapply(tracks, function(t) as.numeric(t$height), numeric(1)))
    # layout() reads a negative height as an ABSOLUTE size in cm (that is all
    # lcm() does); the remaining rows still divide what is left between them in
    # proportion, so the tracks keep their relative heights.
    eh <- .equal_row_in()
    if (is.finite(eh)) {
      # The tracks are sized from the map, not from what is left over: their
      # heights are relative weights against map_weight, so holding that ratio
      # keeps the printed figure in the proportions the app was showing. If the
      # stack does not fit the page, drop back to relative heights - asp = 1
      # still gets the scale right, by centring the map in the row it gets.
      th <- eh * (hts[-1] / as.numeric(map_weight))
      if (all(is.finite(th)) && sum(c(eh, th)) <= graphics::par("din")[2] * 0.98)
        hts <- graphics::lcm(c(eh, th) * 2.54)
    }
    if (isTRUE(legend)) {
      mat <- cbind(c(1L, seq.int(3L, length.out = ntr)), c(2L, rep(0L, ntr)))
      graphics::layout(mat, widths = c(6, 1), heights = hts)      # 1=map 2=legend 3..=tracks
    } else {
      graphics::layout(matrix(seq_len(ntr + 1L), ncol = 1), heights = hts)  # 1=map 2..=tracks
    }
  } else if (isTRUE(legend)) {
    graphics::layout(matrix(c(1, 2), nrow = 1), widths = c(6, 1))
  }

  op <- graphics::par(mar = body_mar); on.exit(graphics::par(op))

  # ---- map body ----
  graphics::plot.new()
  graphics::plot.window(xlim = c(start, end), ylim = c(yend, ystart),
                        xaxs = "i", yaxs = "i", asp = asp_v)
  graphics::rasterImage(ras, start, yend, end, ystart, interpolate = FALSE)
  if (isTRUE(ticks) && !is.null(genome)) {
    .genome_axis(3)
    .genome_axis(2)
  } else if (isTRUE(ticks)) {
    tk <- pretty(c(start, end), n = 6); tk <- tk[tk >= start & tk <= end]
    ty <- pretty(c(ystart, yend), n = 6); ty <- ty[ty >= ystart & ty <= yend]
    # tcl (tick length) is in text-line units, so it stays a fixed physical
    # length regardless of the map/track height or page size; mgp keeps the
    # labels close to the ticks.
    #
    # lwd = 0 draws the ticks WITHOUT the axis line: under equal scaling the
    # plot region can be taller or wider than the map itself, and a full-length
    # axis line would run on past the image. The border below is drawn at the
    # map's own edges instead, so it hugs the picture either way.
    graphics::axis(3, at = tk, labels = fmt_bp(tk), tcl = -0.4, mgp = c(3, 0.5, 0),
                   lwd = 0, lwd.ticks = 1)
    graphics::axis(2, at = ty, labels = fmt_bp(ty), las = 1, tcl = -0.4,
                   mgp = c(3, 0.6, 0), lwd = 0, lwd.ticks = 1)
    graphics::title(ylab = chr_y, line = 3.4)
    if (ntr == 0) graphics::mtext(chr, side = 3, line = 2.3, cex = 1.0)
  }
  .genome_grid()
  .split_marks()
  graphics::rect(start, yend, end, ystart)

  # How tall the map ACTUALLY came out, as margins for the legend column.
  #
  # The colour bar should be the same height as the picture it explains. It
  # normally is - both cells are the same layout row - but under equal scaling
  # the map is centred in its cell and no longer fills it, and a bar running
  # the full height next to a short map looks wrong. So measure where the image
  # landed (par("usr") is the panel's data range, par("plt") its share of the
  # figure) and turn the space above and below it into the legend's top and
  # bottom margins. With no padding this reproduces the old margins exactly.
  leg_mar <- if (isTRUE(ticks)) c(body_mar[1], 0.5, body_mar[3], 3.4)
             else c(0.6, 0.5, 0.6, 3.2)
  if (isTRUE(legend)) {
    u <- graphics::par("usr"); pl <- graphics::par("plt")
    fg <- graphics::par("fig"); din <- graphics::par("din")
    csi <- graphics::par("csi")
    span <- u[4] - u[3]
    if (is.finite(span) && span != 0 && csi > 0) {
      fr <- function(v) pl[3] + (v - u[3]) / span * (pl[4] - pl[3])
      lo <- fr(yend); hi <- fr(ystart)          # ylim is reversed: usr[3] = yend
      if (lo > hi) { tmp <- lo; lo <- hi; hi <- tmp }
      figH <- (fg[4] - fg[3]) * din[2]          # this row's height, in inches
      bot <- lo * figH / csi                    # ... as margin lines
      top <- (1 - hi) * figH / csi
      if (all(is.finite(c(bot, top))) && bot >= 0 && top >= 0 &&
          (hi - lo) * figH > 0.2)               # a sliver of a bar helps nobody
        leg_mar <- c(bot, leg_mar[2], top, leg_mar[4])
    }
  }

  # ---- legend (colour-scale bar) ----
  if (isTRUE(legend)) {
    graphics::par(mar = leg_mar)
    pal <- grDevices::colorRampPalette(
             if (isTRUE(diff)) diff_palette(color) else hic_palette(color))(256)
    graphics::plot.new()
    graphics::plot.window(xlim = c(0, 1), ylim = c(vmin, vmax), yaxs = "i")
    yy <- seq(vmin, vmax, length.out = 257)
    graphics::rect(0, yy[-257], 1, yy[-1], col = pal, border = NA)
    graphics::axis(4, las = 1)
    graphics::box()
  }

  # ---- tracks (each draws itself into the next layout row) ----
  for (t in tracks) {
    dfn <- t$draw
    if (is.function(dfn)) tryCatch(dfn(track_mar), error = function(e) {
      graphics::par(mar = track_mar); graphics::plot.new()   # blank row on failure
    })
  }
  invisible()
}

# Open a PNG or PDF device at width_mm x height_mm, run draw_fn(), close it.
write_export_file <- function(file, fmt = c("pdf", "png"),
                              width_mm = 210, height_mm = 297,
                              dpi = 300, draw_fn) {
  fmt <- match.arg(fmt)
  win <- max(10, as.numeric(width_mm))  / 25.4
  hin <- max(10, as.numeric(height_mm)) / 25.4
  if (fmt == "pdf") {
    grDevices::pdf(file, width = win, height = hin)
  } else {
    grDevices::png(file, width = round(win * dpi), height = round(hin * dpi),
                   res = dpi, bg = "white")
  }
  on.exit(grDevices::dev.off())
  draw_fn()
  invisible(file)
}

# Windows folder picker via PowerShell + .NET FolderBrowserDialog.
# Returns the chosen path, "" if the user cancelled, and throws if PowerShell
# could not be run (so the caller can fall back to utils::choose.dir()).
.pick_dir_windows_ps <- function(default = getwd()) {
  dv <- tryCatch(normalizePath(default, winslash = "\\", mustWork = FALSE),
                 error = function(e) "")
  esc <- function(s) gsub("'", "''", s)                     # PowerShell single-quote escape
  script <- paste(c(
    "Add-Type -AssemblyName System.Windows.Forms | Out-Null",
    "$f = New-Object System.Windows.Forms.FolderBrowserDialog",
    "$f.Description = '出力フォルダを選択'",
    "$f.ShowNewFolderButton = $true",
    sprintf("$f.SelectedPath = '%s'", esc(dv)),
    "$top = New-Object System.Windows.Forms.Form",
    "$top.TopMost = $true",
    "if ($f.ShowDialog($top) -eq [System.Windows.Forms.DialogResult]::OK)",
    "  { [Console]::Out.Write('PATH=' + $f.SelectedPath) } else { [Console]::Out.Write('PATH=') }"
  ), collapse = "\r\n")

  ps <- tempfile(fileext = ".ps1")
  con <- file(ps, open = "wb")
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)                # UTF-8 BOM
  writeBin(charToRaw(enc2utf8(script)), con)
  close(con)
  on.exit(unlink(ps), add = TRUE)

  out <- system2("powershell",
                 c("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", ps),
                 stdout = TRUE, stderr = FALSE)
  txt <- paste(out, collapse = "")
  if (!grepl("^PATH=", txt)) stop("PowerShell folder dialog did not run")
  trimws(sub("^PATH=", "", txt))                            # "" when cancelled
}

# Open a native "choose folder" dialog and return the selected path (or NULL if
# cancelled / unsupported). Runs on the machine hosting R, which for HiCarta is
# the user's own desktop, so the dialog appears locally.
choose_folder_dialog <- function(default = getwd()) {
  if (.Platform$OS.type == "windows") {
    # Prefer a .NET FolderBrowserDialog driven from PowerShell: it renders Unicode
    # (Japanese) correctly, unlike utils::choose.dir() whose caption often shows
    # blank. The script is written as a UTF-8+BOM temp file so PowerShell reads
    # the Japanese text properly. Returns "" on cancel, so we can tell "cancelled"
    # (handled) from "PowerShell unavailable" (fall back to choose.dir).
    res <- tryCatch(.pick_dir_windows_ps(default), error = function(e) NULL)
    if (!is.null(res)) return(if (nzchar(res)) res else NULL)  # dialog ran (path or cancel)
    dv  <- tryCatch(normalizePath(default, winslash = "\\", mustWork = FALSE),
                    error = function(e) "")
    d <- tryCatch(utils::choose.dir(default = dv, caption = "Select output folder"),
                  error = function(e) NA_character_)
    if (length(d) == 1 && !is.na(d) && nzchar(d)) return(d)
    return(NULL)
  }
  if (Sys.info()[["sysname"]] == "Darwin") {
    scr <- 'try
POSIX path of (choose folder with prompt "出力フォルダを選択")
end try'
    d <- tryCatch(system2("osascript", c("-e", shQuote(scr)),
                          stdout = TRUE, stderr = FALSE),
                  error = function(e) character(0))
    d <- trimws(paste(d, collapse = ""))
    if (nzchar(d)) return(sub("/+$", "", d))
    return(NULL)
  }
  # Linux: try zenity if present
  d <- tryCatch(system2("zenity", c("--file-selection", "--directory",
                                     "--title=出力フォルダを選択"),
                        stdout = TRUE, stderr = FALSE),
                error = function(e) character(0))
  d <- trimws(paste(d, collapse = ""))
  if (nzchar(d)) d else NULL
}

# Send a PDF to the OS default printer. Falls back to opening the file so the
# user can print manually. Returns a short status message (Japanese).
print_file <- function(pdf) {
  pdf <- normalizePath(pdf, winslash = "\\", mustWork = FALSE)
  if (.Platform$OS.type == "windows") {
    ok <- tryCatch({
      system2("powershell",
              c("-NoProfile", "-Command",
                sprintf("Start-Process -FilePath '%s' -Verb Print", pdf)),
              stdout = TRUE, stderr = TRUE)
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) return("既定のプリンターに送信しました。")
    tryCatch(utils::browseURL(pdf), error = function(e) NULL)
    return("PDFを開きました。プリンターで印刷してください。")
  }
  if (Sys.info()[["sysname"]] == "Darwin") {
    return(tryCatch({ system2("lpr", shQuote(pdf))
                      "既定のプリンターに送信しました。" },
                    error = function(e) { system2("open", shQuote(pdf)); "PDFを開きました。" }))
  }
  tryCatch({ system2("lpr", shQuote(pdf))
             "既定のプリンターに送信しました。" },
           error = function(e) "印刷に失敗しました。")
}
