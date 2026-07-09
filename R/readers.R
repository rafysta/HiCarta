# ============================================================================
# readers.R  -  Unified Hi-C data readers for HiD contact viewer (v4)
#
# Every reader returns a "region matrix": a numeric matrix whose row names and
# column names are bin labels of the form  "chr:start:end"  (colon separated,
# 1-based start, inclusive end) -- exactly the convention used by rfy_hic2's
# .matrix / .rds files and Draw_matrix.R. This gives one common data model for
# all input formats, so the drawing code never needs to know the source.
#
# Key design point vs. the old Java viewer: we NEVER load the whole genome.
# Readers take (chr, start, end) and return only the requested sub-matrix, so
# high-resolution maps and large genomes stay tractable.
# ============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Build "chr:start:end" labels for uniform bins covering [1, chr_length].
.make_bin_labels <- function(chr, chr_length, bin_size) {
  starts <- seq(1L, chr_length, by = bin_size)
  ends   <- pmin(starts + bin_size - 1L, chr_length)
  sprintf("%s:%d:%d", chr, starts, ends)
}

# Parse "chr:start:end" labels into a data.frame(chr,start,end).
parse_bin_labels <- function(labels) {
  m <- do.call(rbind, strsplit(labels, ":", fixed = TRUE))
  data.frame(
    chr   = m[, 1],
    start = as.numeric(m[, 2]),
    end   = as.numeric(m[, 3]),
    stringsAsFactors = FALSE
  )
}

# Given a full matrix with chr:start:end dimnames, extract a square/rectangular
# region for chr:[start,end] (and optionally a second axis).
subset_region <- function(map, chr, start = 1, end = NA,
                           chr2 = NULL, start2 = NULL, end2 = NULL) {
  loc <- parse_bin_labels(rownames(map))
  if (is.na(end)) end <- max(loc$end[loc$chr == chr])
  reg1 <- which(loc$chr == chr & loc$end >= start & loc$start <= end)

  if (is.null(chr2))  chr2  <- chr
  if (is.null(start2)) start2 <- start
  if (is.null(end2))  end2  <- end
  loc2 <- parse_bin_labels(colnames(map))
  reg2 <- which(loc2$chr == chr2 & loc2$end >= start2 & loc2$start <= end2)

  map[reg1, reg2, drop = FALSE]
}

# ---------------------------------------------------------------------------
# 1) rfy_hic2 .rds   -> readRDS gives a matrix with chr:start:end dimnames
# ---------------------------------------------------------------------------
read_rds_map <- function(path, chr = NULL, start = 1, end = NA, ...) {
  map <- readRDS(path)
  map <- ifelse(is.infinite(map), NA, map)
  if (is.null(chr)) return(map)
  subset_region(map, chr, start, end, ...)
}

# ---------------------------------------------------------------------------
# 2) rfy_hic2 .matrix / .matrix.gz  -> square text matrix, header = chr:start:end
# ---------------------------------------------------------------------------
read_matrix_map <- function(path, chr = NULL, start = 1, end = NA, ...) {
  # data.table::fread transparently handles .gz and is fast.
  dt <- fread(path, header = TRUE, check.names = FALSE)
  rn <- dt[[1]]                      # first column = row labels
  m  <- as.matrix(dt[, -1, with = FALSE])
  rownames(m) <- rn
  # column names come from the header (already chr:start:end)
  m <- ifelse(is.infinite(m), NA, m)
  storage.mode(m) <- "double"
  if (is.null(chr)) return(m)
  subset_region(m, chr, start, end, ...)
}

# ---------------------------------------------------------------------------
# Local cache for remote .hic files. Reading a remote .hic over HTTPS issues a
# range request per tile, which is slow. Download the whole file once to a local
# cache and read from there instead (strawr random-access on a local file is
# fast). Local paths are returned unchanged.
# ---------------------------------------------------------------------------
hic_cache_dir <- function() {
  d <- file.path(getwd(), "_hic_cache")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# Generic: download a remote file once to the cache, preserving its extension.
cache_local <- function(path, ext = tools::file_ext(path)) {
  if (is.null(path) || !grepl("^https?://", path)) return(path)
  key  <- paste0(tools::file_path_sans_ext(basename(path)), "_",
                 abs(sum(utf8ToInt(path))) %% 100000L,
                 if (nzchar(ext)) paste0(".", ext) else "")
  dest <- file.path(hic_cache_dir(), key)
  if (file.exists(dest) && file.info(dest)$size > 0) return(dest)
  tmp <- paste0(dest, ".part")
  utils::download.file(path, tmp, mode = "wb", quiet = FALSE)
  file.rename(tmp, dest)
  dest
}

hic_local <- function(path) cache_local(path, ext = "hic")

# ---------------------------------------------------------------------------
# 3) .hic (Juicer) via strawr -> sparse (bin1,bin2,counts) -> region matrix
#     path may be a local file OR an https:// URL (strawr streams both).
# ---------------------------------------------------------------------------
read_hic_map <- function(path, chr, start = 1, end = NA, resolution = 10000,
                         normalization = "NONE", unit = "BP",
                         chr2 = NULL, start2 = NULL, end2 = NULL) {
  if (!requireNamespace("strawr", quietly = TRUE)) {
    stop("Package 'strawr' is required to read .hic files. Run install_libraries.R")
  }
  if (is.null(chr2))   chr2   <- chr
  if (is.null(start2)) start2 <- start
  if (is.null(end2))   end2   <- end
  if (is.na(end))  end  <- .hic_chrom_length(path, chr)
  if (is.na(end2)) end2 <- .hic_chrom_length(path, chr2)

  # Snap to a resolution / normalization that actually exists in this file.
  # (Each menu dataset is a single-resolution file, so asking for the wrong
  #  resolution yields strawr's "Error finding block data".)
  avail_res <- tryCatch(strawr::readHicBpResolutions(path), error = function(e) NULL)
  if (!is.null(avail_res) && length(avail_res) && !(resolution %in% avail_res)) {
    resolution <- avail_res[which.min(abs(avail_res - resolution))]
  }
  avail_norm <- tryCatch(strawr::readHicNormTypes(path), error = function(e) "NONE")
  if (!(normalization %in% avail_norm)) normalization <- "NONE"

  reg1 <- sprintf("%s:%d:%d", chr,  start,  end)
  reg2 <- sprintf("%s:%d:%d", chr2, start2, end2)

  d <- strawr::straw(normalization, path, reg1, reg2, unit, resolution)
  # d has columns x, y, counts (bin start positions in bp)

  starts1 <- seq(floor((start - 1) / resolution) * resolution,
                 end, by = resolution)
  starts2 <- seq(floor((start2 - 1) / resolution) * resolution,
                 end2, by = resolution)

  lab1 <- sprintf("%s:%d:%d", chr,  starts1 + 1L, starts1 + resolution)
  lab2 <- sprintf("%s:%d:%d", chr2, starts2 + 1L, starts2 + resolution)

  m <- matrix(0, nrow = length(starts1), ncol = length(starts2),
              dimnames = list(lab1, lab2))
  i <- match(d$x, starts1)
  j <- match(d$y, starts2)
  ok <- !is.na(i) & !is.na(j)
  m[cbind(i[ok], j[ok])] <- d$counts[ok]
  # straw returns the upper triangle for intra-chromosome; mirror it
  if (chr == chr2) {
    i2 <- match(d$y, starts1)
    j2 <- match(d$x, starts2)
    ok2 <- !is.na(i2) & !is.na(j2)
    m[cbind(i2[ok2], j2[ok2])] <- d$counts[ok2]
  }
  m
}

.hic_chrom_length <- function(path, chr) {
  info <- strawr::readHicChroms(path)
  as.numeric(info$length[info$name == chr])
}

# List chromosomes & resolutions available in a .hic (for the UI).
hic_metadata <- function(path) {
  list(
    chroms      = strawr::readHicChroms(path),
    resolutions = strawr::readHicBpResolutions(path),
    norms       = tryCatch(strawr::readHicNormTypes(path),
                           error = function(e) c("NONE"))
  )
}

# ---------------------------------------------------------------------------
# 4) hic200-cpp .txt.gz  -> "bin1  bin2  score" with 200 bp bins over I,II,III
#
#    The output stores GLOBAL bin indices. Two ways to map index -> genome:
#      (a) supply the bin-definition file produced by make_bin_def2 (exact), or
#      (b) reconstruct assuming contiguous 'bin_size' bins across the chroms in
#          the given order using chrom lengths (default; VERIFY against a real
#          bin file before trusting coordinates).
# ---------------------------------------------------------------------------
read_hic200_map <- function(path, chr, start = 1, end = NA,
                            bin_size = 200,
                            chrom_lengths = c(I = 5579133, II = 4539804,
                                              III = 2452883),
                            bin_def_file = NULL,
                            chr2 = NULL, start2 = NULL, end2 = NULL) {
  if (is.null(bin_def_file)) {
    bins <- .hic200_bins_from_lengths(chrom_lengths, bin_size)
  } else {
    bins <- .hic200_bins_from_file(bin_def_file)
  }
  # bins: data.frame(index, chr, start, end)  (index is 0- or 1-based global)

  dt <- fread(path, header = FALSE, col.names = c("bin1", "bin2", "score"))

  if (is.null(chr2))   chr2   <- chr
  if (is.null(start2)) start2 <- start
  if (is.null(end2))   end2   <- end
  if (is.na(end))  end  <- max(bins$end[bins$chr == chr])
  if (is.na(end2)) end2 <- max(bins$end[bins$chr == chr2])

  sel1 <- bins[bins$chr == chr  & bins$end >= start  & bins$start <= end,  ]
  sel2 <- bins[bins$chr == chr2 & bins$end >= start2 & bins$start <= end2, ]

  lab1 <- sprintf("%s:%d:%d", sel1$chr, sel1$start, sel1$end)
  lab2 <- sprintf("%s:%d:%d", sel2$chr, sel2$start, sel2$end)
  m <- matrix(0, nrow = nrow(sel1), ncol = nrow(sel2),
              dimnames = list(lab1, lab2))

  keep <- dt$bin1 %in% sel1$index & dt$bin2 %in% sel2$index
  sub  <- dt[keep]
  i <- match(sub$bin1, sel1$index); j <- match(sub$bin2, sel2$index)
  ok <- !is.na(i) & !is.na(j)
  m[cbind(i[ok], j[ok])] <- sub$score[ok]
  # symmetric fill
  keep2 <- dt$bin2 %in% sel1$index & dt$bin1 %in% sel2$index
  sub2  <- dt[keep2]
  i2 <- match(sub2$bin2, sel1$index); j2 <- match(sub2$bin1, sel2$index)
  ok2 <- !is.na(i2) & !is.na(j2)
  m[cbind(i2[ok2], j2[ok2])] <- sub2$score[ok2]
  m
}

.hic200_bins_from_lengths <- function(chrom_lengths, bin_size) {
  out <- list(); idx <- 0L
  for (chr in names(chrom_lengths)) {
    starts <- seq(1L, chrom_lengths[[chr]], by = bin_size)
    ends   <- pmin(starts + bin_size - 1L, chrom_lengths[[chr]])
    n <- length(starts)
    out[[chr]] <- data.frame(index = idx + seq_len(n), chr = chr,
                             start = starts, end = ends,
                             stringsAsFactors = FALSE)
    idx <- idx + n
  }
  do.call(rbind, out)
}

.hic200_bins_from_file <- function(bin_def_file) {
  # Expected: whitespace/tab table with at least (index, chr, start, end).
  bd <- fread(bin_def_file, header = FALSE)
  data.frame(index = bd[[1]], chr = bd[[2]],
             start = as.numeric(bd[[3]]), end = as.numeric(bd[[4]]),
             stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------
# dispatcher: pick reader from file extension / explicit type
# ---------------------------------------------------------------------------
read_map <- function(path, type = c("auto", "hic", "rds", "matrix", "hic200"),
                     ...) {
  type <- match.arg(type)
  if (type == "auto") {
    lp <- tolower(path)
    type <- if (grepl("\\.hic$", lp)) "hic"
            else if (grepl("\\.rds$", lp)) "rds"
            else if (grepl("\\.matrix(\\.gz)?$", lp)) "matrix"
            else if (grepl("\\.txt\\.gz$", lp)) "hic200"
            else stop("Cannot infer file type from: ", path)
  }
  switch(type,
    hic    = read_hic_map(path, ...),
    rds    = read_rds_map(path, ...),
    matrix = read_matrix_map(path, ...),
    hic200 = read_hic200_map(path, ...)
  )
}
