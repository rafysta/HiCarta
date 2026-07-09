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
# `st` is an environment holding: path, chr, chrlen, res (available bp
# resolutions, ascending), norm, color, vmin, vmax, and a cached `blank` tile.
# ============================================================================

TILE_PX <- 256L

choose_res <- function(bpp, res_asc) {
  res_asc[which.min(abs(log2(res_asc) - log2(bpp)))]
}

blank_tile <- function(st) {
  if (!is.null(st$blank)) return(st$blank)
  f <- tempfile(fileext = ".png")
  png(f, width = TILE_PX, height = TILE_PX, bg = "transparent"); dev.off()
  b <- readBin(f, "raw", n = file.info(f)$size); unlink(f)
  st$blank <- b; b
}

render_tile <- function(st, z, x, y) {
  # non-negative zoom: z in 0..maxZoom; at z=maxZoom, 1 pixel = baseRes bp
  bpp     <- st$baseRes * 2^(st$maxZoom - z)   # bp per pixel at this zoom
  bppTile <- TILE_PX * bpp                      # bp spanned by one tile
  x0 <- x * bppTile; x1 <- x0 + bppTile
  y0 <- y * bppTile; y1 <- y0 + bppTile
  if (x0 >= st$chrlen || y0 >= st$chrlen || x1 <= 0 || y1 <= 0)
    return(blank_tile(st))

  res <- choose_res(bpp, st$res)
  xs <- max(1, floor(x0) + 1); xe <- min(st$chrlen, ceiling(x1))
  ys <- max(1, floor(y0) + 1); ye <- min(st$chrlen, ceiling(y1))
  if (xe <= xs || ye <= ys) return(blank_tile(st))

  m <- tryCatch(
    read_hic_map(st$path, chr = st$chr, start = ys, end = ye,
                 resolution = res, normalization = st$norm,
                 chr2 = st$chr, start2 = xs, end2 = xe),
    error = function(e) NULL)
  if (is.null(m) || is.null(dim(m)) || nrow(m) == 0 || ncol(m) == 0)
    return(blank_tile(st))

  locy <- parse_bin_labels(rownames(m))   # y bins (rows)
  locx <- parse_bin_labels(colnames(m))   # x bins (cols)

  px <- 0:(TILE_PX - 1)
  xc <- x0 + (px + 0.5) * bpp              # x-centre bp of each column pixel
  yc <- y0 + (px + 0.5) * bpp             # y-centre bp of each row pixel
  xidx <- findInterval(xc, locx$start)
  yidx <- findInterval(yc, locy$start)
  xidx[xc < 1 | xc > st$chrlen | xidx < 1 | xidx > nrow(locx)] <- NA
  yidx[yc < 1 | yc > st$chrlen | yidx < 1 | yidx > nrow(locy)] <- NA

  val <- matrix(NA_real_, TILE_PX, TILE_PX)  # [row = y pixel, col = x pixel]
  okr <- which(!is.na(yidx)); okc <- which(!is.na(xidx))
  if (length(okr) && length(okc)) val[okr, okc] <- m[yidx[okr], xidx[okc]]

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
  ras  <- grDevices::as.raster(matrix(cols, TILE_PX, TILE_PX))

  f <- tempfile(fileext = ".png")
  png(f, width = TILE_PX, height = TILE_PX, bg = "transparent")
  par(mar = c(0, 0, 0, 0)); plot.new()
  plot.window(c(0, 1), c(0, 1), xaxs = "i", yaxs = "i")
  rasterImage(ras, 0, 0, 1, 1, interpolate = FALSE)
  dev.off()
  b <- readBin(f, "raw", n = file.info(f)$size); unlink(f); b
}
