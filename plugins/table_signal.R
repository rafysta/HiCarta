# ============================================================================
# table_signal.R  -  HiCarta plugin: any chr / start / end / value table
#
# The shortest path from "my own analysis result" to "a track under the map":
# write the numbers to a text file and name it in the catalog. Comma- or
# tab-separated, with or without a header; a bedGraph works as it is.
#
#   chr      start     end       value
#   chr1     1000000   1010000   0.42
#   chr1     1010000   1020000   -0.13
#
# Catalog row:   file_type = table     path = <the .csv / .tsv / .bedgraph>
# (a .csv or .tsv file is recognised by its extension, so file_type may also be
# left empty). Negative values are drawn downwards from a zero line, which is
# what makes this useful for insulation scores, eigenvectors, log-ratios...
#
# Parameters:
#   value_col  which column holds the value (name or 1-based index); 0 = the
#              4th column, or the one named "value" / "score" when there is one
#   style      "bar" (default), "line" or "area"
#   baseline   TRUE = draw the zero line when values cross zero
# ============================================================================

hicarta_plugin(
  id          = "table",
  label       = "Signal table (chr/start/end/value)",
  description = "A comma- or tab-separated table with chr, start, end and a value column, e.g. a bedGraph or any score you computed yourself.",
  accepts     = "any",
  extensions  = c("csv", "tsv"),
  height      = 90,
  color       = "#2166AC",
  defaults    = list(value_col = 0, style = "bar", baseline = TRUE),

  # chromosome lengths from the file itself (track-only mode)
  chroms = function(path) {
    d <- .table_signal_read(path)
    len <- tapply(d$end, d$chr, max)
    stats::setNames(as.numeric(len), names(len))
  },

  read = function(path, chr, start, end, p) {
    d <- .table_signal_read(path)
    # tolerate the usual chr-prefix mismatch (chrII vs II)
    cand <- unique(c(chr, sub("^chr", "", chr), paste0("chr", chr)))
    d <- d[d$chr %in% cand & d$end >= start & d$start <= end, , drop = FALSE]
    vc <- p$value_col
    col <- if (is.character(vc) && nzchar(vc) && vc %in% names(d)) vc
           else if (is.numeric(vc) && vc >= 1 && vc <= ncol(d)) names(d)[vc]
           else if ("value" %in% names(d)) "value"
           else if ("score" %in% names(d)) "score"
           else names(d)[4]
    data.frame(start = d$start, end = d$end,
               value = suppressWarnings(as.numeric(d[[col]])))
  },

  draw = function(d, chr, vstart, vend, style) {
    p <- style$params
    if (is.null(d) || nrow(d) == 0) {
      hc_canvas(vstart, vend); hc_label(style$name)
      hc_message("no rows in view", col = "grey50")
      return(invisible(NULL))
    }
    v <- d$value; v[!is.finite(v)] <- 0
    ymax <- if (is.finite(style$ymax) && style$ymax > 0) style$ymax else max(v, 0)
    ymin <- if (is.finite(style$ymin)) style$ymin else min(v, 0)
    if (ymax <= ymin) ymax <- ymin + 1
    hc_canvas(vstart, vend, ylim = c(ymin, ymax))
    base <- min(max(0, ymin), ymax)
    if (isTRUE(p$baseline) && ymin < 0) abline(h = base, col = "grey70")
    hv <- pmin(pmax(v, ymin), ymax)
    if (identical(p$style, "line")) {
      lines((d$start + d$end) / 2, hv, col = style$color, lwd = 1.5)
    } else if (identical(p$style, "area")) {
      x <- c(d$start[1], (d$start + d$end) / 2, d$end[nrow(d)])
      polygon(c(x, rev(x)), c(base, hv, base, rep(base, length(x))),
              col = grDevices::adjustcolor(style$color, 0.6), border = style$color)
    } else {
      rect(d$start, base, d$end, hv, col = style$color, border = NA)
    }
    hc_label(style$name)
    if (isTRUE(style$print)) hc_yaxis()
    else { if (ymax > 0) hc_guide(signif(ymax * 0.9, 1)); if (ymin < 0) hc_guide(signif(ymin * 0.9, 1)) }
    invisible(NULL)
  }
)

# ---- file reader (cached per file; a table is read once per session) --------
.table_signal_cache <- new.env(parent = emptyenv())
.table_signal_read <- function(path) {
  key <- paste0(path, "|", tryCatch(file.info(path)$mtime, error = function(e) ""))
  hit <- get0(key, envir = .table_signal_cache, ifnotfound = NULL)
  if (!is.null(hit)) return(hit)
  first <- readLines(path, n = 1, warn = FALSE)
  sep   <- if (grepl("\t", first)) "\t" else if (grepl(",", first)) "," else ""
  # header or not: a header's 2nd field is not a number
  f2 <- strsplit(first, if (nzchar(sep)) sep else "[[:space:]]+")[[1]]
  hdr <- length(f2) >= 2 && is.na(suppressWarnings(as.numeric(f2[2])))
  d <- utils::read.table(path, sep = sep, header = hdr, comment.char = "#",
                         quote = "\"", stringsAsFactors = FALSE,
                         check.names = FALSE)
  if (ncol(d) < 4) stop("need at least 4 columns: chr, start, end, value")
  if (!hdr) names(d)[1:4] <- c("chr", "start", "end", "value")
  names(d)[1:3] <- c("chr", "start", "end")
  d$chr   <- as.character(d$chr)
  d$start <- suppressWarnings(as.numeric(d$start))
  d$end   <- suppressWarnings(as.numeric(d$end))
  d <- d[is.finite(d$start) & is.finite(d$end), , drop = FALSE]
  assign(key, d, envir = .table_signal_cache)
  d
}
