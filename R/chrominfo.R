# ============================================================================
# chrominfo.R  -  derive a coordinate system from a 1-D track file.
#
# Normally HiCarta takes chromosome names and lengths from the .hic file. When
# the user wants to look at tracks WITHOUT a contact map, we have to get that
# information from the track itself:
#
#   bigWig          : the file header (seqlengths) - exact and cheap
#   BED / bedGraph  : header if present, else the largest end coordinate seen
#   gene (GFF3)     : largest gene end per chromosome (from the parsed cache)
#   BorderStrength  : largest bin end per chromosome (from the parsed cache)
#
# track_chrom_info() returns a NAMED numeric vector  c(<chr> = <length>, ...)
# in file order (so [1] is the first chromosome of the file), or NULL when the
# file gives us nothing usable. When it comes back empty,
# track_chrom_info_why() says what was tried and how each attempt failed - a
# bare "no chromosome information" left the user with nothing to act on, since
# a missing rtracklayer, an unreachable URL and a file that is not really a
# bigWig all looked exactly the same.
# ============================================================================

# --- why the last call came back empty (read by app.R's add_track) ----------
.CHROMINFO <- new.env(parent = emptyenv())
.chrominfo_reset <- function() assign("why", character(0), envir = .CHROMINFO)
.chrominfo_note <- function(what, e = NULL) {
  msg <- if (is.null(e)) what
         else sprintf("%s: %s",
                      what,
                      if (inherits(e, "condition")) conditionMessage(e)
                      else as.character(e))
  assign("why", c(get0("why", .CHROMINFO, ifnotfound = character(0)), msg),
         envir = .CHROMINFO)
}
track_chrom_info_why <- function()
  # unique(): the bigWig branch and the generic branch can hit the same wall
  # (a missing rtracklayer), and saying so twice helps nobody
  paste(unique(get0("why", .CHROMINFO, ifnotfound = character(0))),
        collapse = " / ")

# max end per chromosome, keeping first-appearance (= file) order
.chrom_from_cols <- function(chr, end) {
  chr <- as.character(chr); end <- suppressWarnings(as.numeric(end))
  ok  <- !is.na(chr) & nzchar(chr) & is.finite(end)
  chr <- chr[ok]; end <- end[ok]
  if (length(chr) == 0) return(NULL)
  nm  <- unique(chr)
  len <- vapply(nm, function(cc) max(end[chr == cc]), numeric(1))
  len <- len[is.finite(len) & len > 0]
  if (length(len) == 0) return(NULL)
  stats::setNames(as.numeric(len), names(len))
}

# seqlengths from a GRanges / Seqinfo, dropping the usual NA entries
.chrom_from_seqinfo <- function(x) {
  len <- tryCatch(GenomeInfoDb::seqlengths(x), error = function(e) NULL)
  if (is.null(len) || length(len) == 0) return(NULL)
  len <- len[!is.na(len) & len > 0]
  if (length(len) == 0) return(NULL)
  stats::setNames(as.numeric(len), names(len))
}

track_chrom_info <- function(path, type = "bigWig") {
  type <- as.character(type)[1]
  .chrominfo_reset()

  # ---- already-parsed formats: use the cached table ------------------------
  if (identical(type, "gene")) {
    g <- tryCatch(read_genes(path)$genes,
                  error = function(e) { .chrominfo_note("GFF3", e); NULL })
    if (is.null(g) || nrow(g) == 0) {
      if (!is.null(g)) .chrominfo_note("GFF3 holds no gene")
      return(NULL)
    }
    return(.chrom_from_cols(g$chr, g$end))
  }
  if (identical(type, "BorderStrength")) {
    d <- tryCatch(read_bs(path),
                  error = function(e) { .chrominfo_note("Border Strength", e); NULL })
    if (is.null(d) || nrow(d) == 0) {
      if (!is.null(d)) .chrominfo_note("Border Strength file is empty")
      return(NULL)
    }
    return(.chrom_from_cols(d$chr, d$end))
  }

  # ---- bigWig: the header knows the chromosome lengths ---------------------
  # The BBI chromosome B+ tree names every chromosome with its exact length,
  # so a bigWig alone is enough to establish the coordinate system — no
  # separate chrom-sizes file needed. The native reader parses it for local
  # files AND http(s) URLs (rtracklayer, the fallback, is local-only).
  #
  # The gate is the declared TYPE as well as the file name: a bigWig behind a
  # URL that carries a query string, or one named .bigwig.bw or .bw.tmp, is
  # still a bigWig, and testing the extension alone sent those straight to
  # rtracklayer - which cannot open a remote bigWig at all - and then reported
  # "no chromosome information" as if the file were at fault.
  if (identical(type, "bigWig") || grepl("\\.(bw|bigwig)$", tolower(path))) {
    if (exists("bw_reader")) {
      ci <- tryCatch({
        ch <- bw_chroms(bw_reader(path))
        stats::setNames(as.numeric(ch$size), as.character(ch$name))
      }, error = function(e) { .chrominfo_note("bigWig reader", e); NULL })
      if (!is.null(ci) && length(ci) > 0) return(ci)
      if (!is.null(ci)) .chrominfo_note("bigWig header lists no chromosome")
    } else .chrominfo_note("R/bigwig_reader.R is not loaded")
    if (requireNamespace("rtracklayer", quietly = TRUE) &&
        requireNamespace("GenomeInfoDb", quietly = TRUE)) {
      si <- tryCatch(GenomeInfoDb::seqinfo(rtracklayer::BigWigFile(path)),
                     error = function(e) { .chrominfo_note("rtracklayer", e); NULL })
      ci <- if (is.null(si)) NULL else .chrom_from_seqinfo(si)
      if (!is.null(ci)) return(ci)
    } else .chrominfo_note("rtracklayer is not installed")
  }

  # ---- anything else (BED / bedGraph / headerless): read it once and take
  #      the largest coordinate per chromosome.
  if (!requireNamespace("rtracklayer", quietly = TRUE)) {
    .chrominfo_note("rtracklayer is not installed")
    return(NULL)
  }
  gr <- tryCatch(rtracklayer::import(path),
                 error = function(e) { .chrominfo_note("rtracklayer::import", e); NULL })
  if (is.null(gr) || length(gr) == 0) {
    if (!is.null(gr)) .chrominfo_note("the file holds no interval")
    return(NULL)
  }
  ci <- .chrom_from_seqinfo(gr)
  if (!is.null(ci)) return(ci)
  ci <- .chrom_from_cols(as.character(GenomicRanges::seqnames(gr)),
                         GenomicRanges::end(gr))
  if (is.null(ci)) .chrominfo_note("no usable chromosome name / end coordinate")
  ci
}
