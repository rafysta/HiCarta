# ============================================================================
# export.R  -  Publication / print export of a Hi-C contact map.
#
# Renders a chosen region (chr:start:end) as a square contact map (Hi-C uses the
# SAME range on both axes) to the current graphics device, then to a PNG or PDF
# file at a requested paper size, or straight to the default printer. It reuses
# the interactive view's global colour scale (vmin/vmax, palette) so the exported
# image matches what is on screen.
#
# Public functions
#   read_export_matrix(st, chr, start, end)  -> list(m, res)
#   draw_export_map(m, chr, start, end, ...)  -> draws to current device
#   write_export_file(file, fmt, width_mm, height_mm, dpi, draw_fn)
#   print_file(pdf)                           -> send a PDF to the default printer
#
# `st` is the tile-render state environment from app.R (path, chr, chrlen, res,
# norm, color, vmin, vmax, ovres).
# ============================================================================

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Format a bp value as a short axis label (Mb / kb / bp).
fmt_bp <- function(v) {
  vapply(v, function(x) {
    ax <- abs(x)
    if (ax >= 1e6)      paste0(format(round(x / 1e6, 2), trim = TRUE, nsmall = 0), " Mb")
    else if (ax >= 1e3) paste0(format(round(x / 1e3, 1), trim = TRUE, nsmall = 0), " kb")
    else                as.character(round(x))
  }, character(1))
}

# Read a square, same-range region matrix for export. Picks a .hic resolution so
# the region spans ~target_bins bins (capped so the straw read stays reasonable).
#
# With a comparison sample attached and st$cmpMode == "split", the two samples
# are merged exactly as on screen: the upper-right triangle (column >= row, i.e.
# genomic x >= y) comes from A and the lower-left from B, with B multiplied by
# st$bfac to match A's sequencing depth. The returned `split` flag lets the
# caller know it should also draw the diagonal / corner labels.
read_export_matrix <- function(st, chr, start, end, target_bins = 1500) {
  start <- max(1, as.numeric(start)); end <- as.numeric(end)
  span  <- max(1, end - start + 1)
  res   <- choose_res(span / target_bins, st$res)          # nearest available res
  if (span / res > 4000) {                                  # keep matrix tractable
    res <- st$res[which.min(abs(st$res - span / 2000))]
  }
  # virtual multi-resolution dataset: this resolution's file + its brightness
  # factor (see tiles.R); ordinary single files pass straight through
  pA <- .vpath_a(st, res)
  m <- read_hic_map(pA, chr = chr, start = start, end = end,
                    resolution = res, normalization = st$norm,
                    chr2 = chr, start2 = start, end2 = end)  # square, same range
  m <- m * .vfac_a(st, pA)

  has_b <- !is.null(st$path2) && nzchar(st$path2)
  split <- identical(st$cmpMode, "split") && has_b
  diff  <- identical(st$cmpMode, "diff")  && has_b
  if (split || diff) {
    mb <- tryCatch(
      read_hic_map(st$path2, chr = chr, start = start, end = end,
                   resolution = res, normalization = st$norm2,
                   chr2 = chr, start2 = start, end2 = end),
      error = function(e) NULL)
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
draw_export_map <- function(m, chr, start, end,
                            color = "matlab", vmin = 0, vmax = 1,
                            ticks = TRUE, legend = TRUE, no_margin = FALSE,
                            tracks = list(), map_weight = 720,
                            diagonal = FALSE, label_a = NULL, label_b = NULL,
                            diff = FALSE) {
  start <- max(1, as.numeric(start)); end <- as.numeric(end)

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
    graphics::plot.window(xlim = c(start, end), ylim = c(end, start),
                          xaxs = "i", yaxs = "i")
    graphics::rasterImage(ras, start, end, end, start, interpolate = FALSE)
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

  # ---- figure layout: map row on top, one row per track, optional legend col.
  if (ntr > 0) {
    hts <- c(as.numeric(map_weight), vapply(tracks, function(t) as.numeric(t$height), numeric(1)))
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
  graphics::plot.window(xlim = c(start, end), ylim = c(end, start),
                        xaxs = "i", yaxs = "i")
  graphics::rasterImage(ras, start, end, end, start, interpolate = FALSE)
  if (isTRUE(ticks)) {
    tk <- pretty(c(start, end), n = 6); tk <- tk[tk >= start & tk <= end]
    # tcl (tick length) is in text-line units, so it stays a fixed physical
    # length regardless of the map/track height or page size; mgp keeps the
    # labels close to the ticks.
    graphics::axis(3, at = tk, labels = fmt_bp(tk), tcl = -0.4, mgp = c(3, 0.5, 0))
    graphics::axis(2, at = tk, labels = fmt_bp(tk), las = 1, tcl = -0.4, mgp = c(3, 0.6, 0))
    graphics::title(ylab = chr, line = 3.4)
    if (ntr == 0) graphics::mtext(chr, side = 3, line = 2.3, cex = 1.0)
  }
  .split_marks()
  graphics::box()

  # ---- legend (colour-scale bar) ----
  if (isTRUE(legend)) {
    graphics::par(mar = if (isTRUE(ticks)) c(body_mar[1], 0.5, body_mar[3], 3.4)
                        else c(0.6, 0.5, 0.6, 3.2))
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
