# ============================================================================
# draw.R  -  Contact-map rendering, ported from rfy_hic2 Draw_matrix.R
#
# draw_contact_map() takes a region matrix (chr:start:end dimnames) and renders
# it with the same visual language as Draw_matrix.R: named palettes, percentile
# or absolute value scaling, optional distance (observed/expected) normalization,
# NA/zero handling and triangle-only display. It draws to the CURRENT graphics
# device, so it works for both Shiny renderPlot() and png()/pdf() export.
# ============================================================================

# --- palettes (identical anchors to Draw_matrix.R) --------------------------
hic_palette <- function(name = "matlab") {
  if (name == "matlab") {
    c("#00007F", "blue", "#007FFF", "cyan", "#7FFF7F",
      "yellow", "#FF7F00", "red", "#7F0000")
  } else if (name == "gentle") {
    rev(RColorBrewer::brewer.pal(10, "RdBu"))
  } else if (name == "red") {
    RColorBrewer::brewer.pal(9, "Reds")
  } else if (name == "blue") {
    RColorBrewer::brewer.pal(9, "Blues")
  } else {
    c("#00007F", "blue", "#007FFF", "cyan", "#7FFF7F",
      "yellow", "#FF7F00", "red", "#7F0000")
  }
}

.take_middle <- function(mat, lo, hi) {
  mat <- ifelse(mat < lo, lo, mat)
  ifelse(mat > hi, hi, mat)
}

# rotate so that image() shows the map in the conventional orientation
.transform <- function(mat) {
  d <- dim(mat)[1]
  t(mat[d + 1 - seq_len(d), , drop = FALSE])
}

# observed / expected by genomic distance (Draw_matrix.R "distance")
.observed_over_expected <- function(map, log2 = FALSE) {
  n <- nrow(map)
  exp <- map
  for (d in 0:(n - 1)) {
    i1 <- 1:(n - d); i2 <- i1 + d
    a  <- mean(as.numeric(map[cbind(i1, i2)]), na.rm = TRUE)
    exp[cbind(i1, i2)] <- a
    exp[cbind(i2, i1)] <- a
  }
  r <- ifelse(exp == 0, NA, map / exp)
  if (log2) r <- log2(r)
  r
}

#' Draw a Hi-C contact map to the current device.
#'
#' @param map region matrix with chr:start:end dimnames
#' @param color one of matlab/gentle/red/blue
#' @param unit  "p" percentile (min/max are quantiles) or "v" absolute value
#' @param min,max scaling bounds (percentile 0..1 when unit="p"; default max .95)
#' @param na    how to fill NA: "min","zero","na"
#' @param oe    FALSE, "oe" (observed/expected), or "oe_log2"
#' @param triangle draw only the upper triangle
draw_contact_map <- function(map,
                             color = "matlab",
                             unit  = "p",
                             min   = NULL,
                             max   = 0.95,
                             na    = "min",
                             oe    = FALSE,
                             triangle = FALSE,
                             title = NULL) {
  map <- ifelse(is.infinite(map), NA, map)

  if (identical(oe, "oe"))       map <- .observed_over_expected(map, FALSE)
  else if (identical(oe, "oe_log2")) map <- .observed_over_expected(map, TRUE)

  ex <- map

  # scaling bounds
  if (unit == "p") {
    num <- sort(as.numeric(ex), na.last = NA)
    q <- function(p) {
      if (p > 1) p <- p / 100
      r <- round(length(num) * p); if (r == 0) r <- 1
      num[r]
    }
    Min <- if (is.null(min)) min(ex, na.rm = TRUE) else q(as.numeric(min))
    Max <- if (is.null(max)) max(ex, na.rm = TRUE) else q(as.numeric(max))
  } else {
    Min <- if (is.null(min)) min(ex, na.rm = TRUE) else as.numeric(min)
    Max <- if (is.null(max)) max(ex, na.rm = TRUE) else as.numeric(max)
  }

  # NA handling
  if (na == "min") {
    ex <- ifelse(is.na(ex), min(ex, na.rm = TRUE), ex)
  } else if (na == "zero") {
    ex <- ifelse(is.na(ex), 0, ex)
  }

  conv <- .take_middle(ex, Min, Max)
  if (triangle) {
    conv[lower.tri(conv, diag = TRUE)] <- NA
  }

  # colour breaks: dense up to the 95th percentile, log-spaced tail (Draw_matrix.R)
  lseq <- function(from, to, length.out) if (from == to) from else exp(seq(log(from), log(to), length.out = length.out))
  tmp <- as.numeric(conv); tmp <- tmp[!is.na(tmp)]
  if (length(tmp) == 0) { plot.new(); return(invisible()) }
  T95 <- sort(tmp)[max(1, round(length(tmp) * 0.95))]
  bk <- unique(c(seq(Min, T95, length.out = 95), lseq(T95, Max + 1, length.out = 5)))
  if (length(bk) < 2) bk <- c(Min, Max + 1)

  cat_m <- matrix(as.integer(cut(conv, breaks = bk, include.lowest = TRUE)),
                  nrow = nrow(conv))
  cols <- colorRampPalette(hic_palette(color))(length(bk))
  lo <- min(cat_m, na.rm = TRUE); hi <- max(cat_m, na.rm = TRUE)
  cols <- cols[lo:hi]

  op <- par(oma = c(0, 0, if (is.null(title)) 0 else 2, 0), mar = c(0, 0, 0, 0))
  on.exit(par(op))
  image(.transform(cat_m), col = cols, axes = FALSE, useRaster = TRUE)
  if (!is.null(title)) mtext(title, side = 3, line = 0.3, cex = 1.1, outer = TRUE)
  invisible(list(min = Min, max = Max))
}

# ---------------------------------------------------------------------------
# map_to_color_matrix(): return a matrix of hex colours in the SAME orientation
# as `map` (element [i,j] = colour for bin i,j). Used by the Leaflet/pan viewer
# to build a PNG raster. Shares the scaling logic with draw_contact_map().
# ---------------------------------------------------------------------------
map_to_color_matrix <- function(map, color = "matlab", unit = "p",
                                min = NULL, max = 0.95, na = "min",
                                oe = FALSE, triangle = FALSE) {
  map <- ifelse(is.infinite(map), NA, map)
  if (identical(oe, "oe"))            map <- .observed_over_expected(map, FALSE)
  else if (identical(oe, "oe_log2"))  map <- .observed_over_expected(map, TRUE)
  ex <- map

  if (unit == "p") {
    num <- sort(as.numeric(ex), na.last = NA)
    q <- function(p) { if (p > 1) p <- p / 100; r <- round(length(num) * p); if (r == 0) r <- 1; num[r] }
    Min <- if (is.null(min)) min(ex, na.rm = TRUE) else q(as.numeric(min))
    Max <- if (is.null(max)) max(ex, na.rm = TRUE) else q(as.numeric(max))
  } else {
    Min <- if (is.null(min)) min(ex, na.rm = TRUE) else as.numeric(min)
    Max <- if (is.null(max)) max(ex, na.rm = TRUE) else as.numeric(max)
  }
  if (na == "min")  ex <- ifelse(is.na(ex), min(ex, na.rm = TRUE), ex)
  else if (na == "zero") ex <- ifelse(is.na(ex), 0, ex)

  conv <- .take_middle(ex, Min, Max)
  if (triangle) conv[lower.tri(conv, diag = TRUE)] <- NA

  tmp <- as.numeric(conv); tmp <- tmp[is.finite(tmp)]
  if (length(tmp) == 0) return(matrix("#FFFFFF", nrow(map), ncol(map)))
  if (!is.finite(Min)) Min <- min(tmp)
  if (!is.finite(Max)) Max <- max(tmp)
  if (Max <= Min) Max <- Min + 1e-9
  # Linear colour scale: Min -> palette start, Max -> palette end. A Max far
  # above the data therefore keeps the map near the low (e.g. blue) end.
  bk <- seq(Min, Max, length.out = 100)

  cat_i <- matrix(as.integer(cut(conv, breaks = bk, include.lowest = TRUE)),
                  nrow = nrow(conv))
  cols <- colorRampPalette(hic_palette(color))(length(bk))
  out <- matrix(cols[cat_i], nrow = nrow(conv), ncol = ncol(conv))
  out[is.na(out)] <- "#FFFFFF"
  dimnames(out) <- dimnames(map)
  out
}

# Map a numeric vector to palette colours on a LINEAR absolute scale [vmin,vmax].
# NA values become fully transparent. Used by the tiled (high-resolution) viewer
# where every tile must share the same global Min/Max so tiles line up seamlessly.
values_to_colors <- function(vals, color = "matlab", vmin = 0, vmax = 1) {
  if (!is.finite(vmin)) vmin <- 0
  if (!is.finite(vmax) || vmax <= vmin) vmax <- vmin + 1e-9
  pal <- colorRampPalette(hic_palette(color))(256)
  v <- pmin(pmax(vals, vmin), vmax)
  idx <- floor((v - vmin) / (vmax - vmin) * 255) + 1
  idx[is.na(idx) | idx < 1] <- 1L; idx[idx > 256] <- 256L
  out <- pal[idx]
  out[is.na(vals)] <- "#00000000"   # transparent where there is no data
  out
}

# Write a colour matrix to a PNG raster for Leaflet imageOverlay.
# Row 1 (genomic bin 1) becomes the TOP of the image and column 1 the LEFT, so
# the origin sits at the top-left. The app negates latitude when placing the
# overlay, so increasing genomic y runs downward. 1 px per bin.
write_map_png <- function(color_matrix, file) {
  N <- nrow(color_matrix); M <- ncol(color_matrix)
  ras <- grDevices::as.raster(color_matrix)
  png(file, width = M, height = N, units = "px", bg = "transparent")
  op <- par(mar = c(0, 0, 0, 0)); on.exit({ par(op); dev.off() })
  plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1), xaxs = "i", yaxs = "i")
  rasterImage(ras, 0, 0, 1, 1, interpolate = FALSE)
  invisible(file)
}

# Convenience: render to a publication PNG (or PDF).
export_contact_map <- function(map, file, width = 1200, height = NULL,
                               res = 150, ...) {
  if (is.null(height)) height <- round(width / ncol(map) * nrow(map))
  is_pdf <- grepl("\\.pdf$", tolower(file))
  if (is_pdf) {
    pdf(file, width = width / res, height = height / res)
  } else {
    png(file, width = width, height = height, units = "px", bg = "white")
  }
  on.exit(dev.off())
  draw_contact_map(map, ...)
  invisible(file)
}
