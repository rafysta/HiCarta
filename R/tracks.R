# ============================================================================
# tracks.R  -  1-D genome tracks (bigWig signal, BED intervals) drawn below the
# Hi-C map and synced to its x (horizontal) view range.
#
# Only the visible window is read on each draw (rtracklayer 'which' query), so
# tracks stay light even for genome-wide files. A track spec is a list:
#   list(id, name, path, type = "bigWig"|"BED", color, height)
# ============================================================================

# Parse an IGV-style track-list XML:
#   <Global><Category name="..."><Resource name="X" path="Y.bw"/>...</Category></Global>
# Returns data.frame(name, path, type) with type inferred from the extension.
parse_igv_xml <- function(src) {
  con <- if (grepl("^https?://", src)) url(src) else src
  txt <- paste(readLines(con, warn = FALSE), collapse = "\n")
  getattr <- function(x, a) {
    ok <- grepl(paste0(a, '="'), x); out <- rep(NA_character_, length(x))
    out[ok] <- sub(paste0('.*?', a, '="([^"]*)".*'), "\\1", x[ok], perl = TRUE); out
  }
  # split into <Category> blocks so each Resource keeps its category (XML order)
  blocks <- strsplit(txt, "<Category", fixed = TRUE)[[1]]
  out <- list()
  for (blk in blocks) {
    res <- regmatches(blk, gregexpr("<Resource[^>]*>", blk, perl = TRUE))[[1]]
    if (length(res) == 0) next
    m <- regexpr('name="[^"]*"', blk, perl = TRUE)   # first name attr = the Category name
    catname <- if (m > 0) sub('name="([^"]*)"', "\\1", regmatches(blk, m)) else "(uncategorized)"
    nm <- getattr(res, "name"); pt <- getattr(res, "path")
    keep <- !is.na(pt); nm <- nm[keep]; pt <- pt[keep]
    nm[is.na(nm)] <- basename(pt[is.na(nm)])
    ext  <- tolower(tools::file_ext(pt))
    type <- ifelse(ext %in% c("bed", "narrowpeak", "broadpeak"), "BED", "bigWig")
    out[[length(out) + 1]] <- data.frame(category = catname, name = nm,
                                         path = pt, type = type, stringsAsFactors = FALSE)
  }
  if (length(out) == 0)
    return(data.frame(category = character(0), name = character(0),
                      path = character(0), type = character(0)))
  do.call(rbind, out)
}

# Read a track over [start,end] on `chr`. Tries the chromosome name as given and
# common variants (chrII <-> II) so naming differences don't silently blank out.
.track_import <- function(path, chr, start, end) {
  start <- max(1, floor(start)); end <- ceiling(end)
  cand <- unique(c(chr, sub("^chr", "", chr), paste0("chr", chr)))
  for (cc in cand) {
    gr <- tryCatch(
      rtracklayer::import(path,
        which = GenomicRanges::GRanges(cc, IRanges::IRanges(start, end))),
      error = function(e) NULL)
    if (!is.null(gr) && length(gr) > 0) return(gr)
  }
  NULL
}

# Draw one track. The x-axis spans the FULL map view [vstart,vend] (which may run
# past the chromosome ends, so it stays aligned with the contact map); signal is
# only drawn within [1, chrlen]. `nbins` = number of bins across the view.
# spec$ymax > 0 fixes the vertical scale (else it auto-scales to the view).
plot_track <- function(spec, chr, vstart, vend, chrlen = Inf, nbins = 1000) {
  op <- par(mar = c(0.3, 0, 0.3, 0)); on.exit(par(op))
  dstart <- max(1, floor(vstart)); dend <- min(chrlen, ceiling(vend))
  gr <- if (dend > dstart) .track_import(spec$path, chr, dstart, dend) else NULL
  Wpx <- tryCatch(grDevices::dev.size("px")[1], error = function(e) 800)
  gutfrac <- (66 + 8) / Wpx                     # keep labels left of the y-ruler gutter
  lx <- vstart + (1 - gutfrac) * (vend - vstart)

  if (identical(spec$type, "BED")) {
    plot(NA, xlim = c(vstart, vend), ylim = c(0, 1),
         xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)
    if (!is.null(gr) && length(gr) > 0) {
      xs <- pmax(dstart, GenomicRanges::start(gr))
      xe <- pmin(dend,   GenomicRanges::end(gr))
      rect(xs, 0.30, xe, 0.70, col = spec$color, border = NA)
    }
    text(vstart + 0.005 * (vend - vstart), 0.90, spec$name,
         adj = c(0, 1), cex = 1.15, col = "grey20")
  } else {
    nbins   <- max(2L, as.integer(nbins))
    centers <- seq(dstart, dend, length.out = nbins)
    val <- rep(0, nbins)
    if (!is.null(gr) && length(gr) > 0) {
      rs <- GenomicRanges::start(gr); re <- GenomicRanges::end(gr)
      sv <- GenomicRanges::score(gr)
      idx <- findInterval(centers, rs)
      inside <- idx >= 1 & idx <= length(rs) & centers <= re[pmax(idx, 1)]
      val[inside] <- sv[idx[inside]]
    }
    ymax <- if (!is.null(spec$ymax) && is.finite(spec$ymax) && spec$ymax > 0) spec$ymax
            else { m <- suppressWarnings(max(val, na.rm = TRUE)); if (!is.finite(m) || m <= 0) 1 else m }
    plot(NA, xlim = c(vstart, vend), ylim = c(0, ymax * 1.05),
         xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)
    if (dend > dstart) {
      binw <- (dend - dstart) / nbins
      rect(centers - binw / 2, 0, centers + binw / 2, pmin(val, ymax),
           col = spec$color, border = NA)
    }
    # name (top-left, larger) + a round score label at ~90% height on the right
    text(vstart + 0.005 * (vend - vstart), ymax * 1.0, spec$name,
         adj = c(0, 1), cex = 1.15, col = "grey20")
    nice <- signif(ymax * 0.9, 1)
    if (is.finite(nice) && nice > 0) {
      segments(lx, nice, vstart + (1 - 4 / Wpx) * (vend - vstart), nice, col = "grey45")
      text(lx, nice, sprintf("%.3g ", nice), adj = c(1, 0.5), cex = 1.0, col = "grey20")
    }
  }
  box(col = "grey85")
}
