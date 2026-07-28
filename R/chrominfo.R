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
# file gives us nothing usable.
# ============================================================================

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

  # ---- already-parsed formats: use the cached table ------------------------
  if (identical(type, "gene")) {
    g <- tryCatch(read_genes(path)$genes, error = function(e) NULL)
    if (is.null(g) || nrow(g) == 0) return(NULL)
    return(.chrom_from_cols(g$chr, g$end))
  }
  if (identical(type, "BorderStrength")) {
    d <- tryCatch(read_bs(path), error = function(e) NULL)
    if (is.null(d) || nrow(d) == 0) return(NULL)
    return(.chrom_from_cols(d$chr, d$end))
  }

  # ---- bigWig: the header knows the chromosome lengths ---------------------
  if (grepl("\\.(bw|bigwig)$", tolower(path))) {
    si <- tryCatch(GenomeInfoDb::seqinfo(rtracklayer::BigWigFile(path)),
                   error = function(e) NULL)
    ci <- if (is.null(si)) NULL else .chrom_from_seqinfo(si)
    if (!is.null(ci)) return(ci)
  }

  # ---- anything else (BED / bedGraph / headerless): read it once and take
  #      the largest coordinate per chromosome.
  gr <- tryCatch(rtracklayer::import(path), error = function(e) NULL)
  if (is.null(gr) || length(gr) == 0) return(NULL)
  ci <- .chrom_from_seqinfo(gr)
  if (!is.null(ci)) return(ci)
  .chrom_from_cols(as.character(GenomicRanges::seqnames(gr)),
                   GenomicRanges::end(gr))
}
