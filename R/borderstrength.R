# ============================================================================
# borderstrength.R  -  Border Strength track (github.com/rafysta/BorderStrength)
#
# Input: a *_BS.txt with columns  chr, start, end, BS, BS.norm, boundary, TADid, TAD
# (200 bp bins). We plot BS.norm as a filled area: positive = red, negative = blue,
# with a dashed vertical line at every boundary bin. Mirrors drawBW(type=
# "BorderStrength") from hic_graph.R.
#
# The whole file (~62k rows) is small, so it is read once and cached in memory.
# ============================================================================

suppressWarnings(suppressMessages({ library(data.table) }))

BS_CACHE <- new.env(parent = emptyenv())

read_bs <- function(path) {
  if (!is.null(BS_CACHE[[path]])) return(BS_CACHE[[path]])
  d <- data.table::fread(path, header = TRUE, na.strings = c("NA", "", "NaN"))
  val <- suppressWarnings(as.numeric(trimws(as.character(d[["BS.norm"]]))))
  bnd <- suppressWarnings(as.integer(d[["boundary"]]))
  df <- data.frame(chr = as.character(d[["chr"]]),
                   start = as.numeric(d[["start"]]), end = as.numeric(d[["end"]]),
                   val = val, boundary = bnd, stringsAsFactors = FALSE)
  BS_CACHE[[path]] <- df
  df
}

# Draw the Border Strength track for chr:[vstart,vend]; x-axis matches the map.
plot_bs_track <- function(df, chr, vstart, vend, chrlen = Inf, name = "BorderStrength",
                          poscol = "#E4211C", negcol = "#2C6FBF",
                          mar = c(0.3, 0, 0.3, 0), frame = TRUE, yscale = "inline") {
  op <- par(mar = mar); on.exit(par(op))
  vstart <- floor(vstart); vend <- ceiling(vend)
  sub <- df[df$chr == chr & df$end >= vstart & df$start <= vend, , drop = FALSE]
  fv <- sub$val[is.finite(sub$val)]
  ymax <- if (length(fv)) max(abs(fv)) else 1
  if (!is.finite(ymax) || ymax <= 0) ymax <- 1

  plot(NA, xlim = c(vstart, vend), ylim = c(-ymax * 1.05, ymax * 1.05),
       xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)
  if (nrow(sub) > 0) {
    v <- sub$val; v[!is.finite(v)] <- 0
    pos <- v > 0; neg <- v < 0
    if (any(pos)) rect(sub$start[pos], 0, sub$end[pos], v[pos], col = poscol, border = NA)
    if (any(neg)) rect(sub$start[neg], 0, sub$end[neg], v[neg], col = negcol, border = NA)
    bnd <- sub[!is.na(sub$boundary) & sub$boundary != 0, , drop = FALSE]
    if (nrow(bnd) > 0)
      abline(v = (bnd$start + bnd$end) / 2, lty = 2, col = "grey25", lwd = 1)
  }
  abline(h = 0, col = "grey55", lwd = 0.7)
  text(vstart + 0.005 * (vend - vstart), ymax * 0.98, name, adj = c(0, 1), cex = 1.1, col = "grey20")
  if (identical(yscale, "axis")) {
    at <- pretty(c(-ymax, ymax), 3)
    axis(2, at = at, labels = formatC(at, format = "g", digits = 3), las = 1,
         tcl = -0.4, mgp = c(3, 0.5, 0), cex.axis = 0.8, col = "grey40", col.axis = "grey20")
  } else {
    Wpx <- tryCatch(grDevices::dev.size("px")[1], error = function(e) 900)
    nice <- signif(ymax, 2)
    text(vstart + (1 - (66 + 6) / Wpx) * (vend - vstart), ymax * 0.9,
         sprintf("%.3g ", nice), adj = c(1, 0.5), cex = 0.95, col = "grey30")
  }
  if (isTRUE(frame)) box(col = "grey85")
}
