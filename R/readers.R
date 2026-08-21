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
# Local cache for remote files.
#
# This used to be the only way to make remote .hic usable, because strawr is
# stateless: it reopens the URL four times per query and, worse,
# strawr::readHicNormTypes() has no HTTP code path at all -- it reads from the
# never-opened local ifstream, parses garbage lengths and spins for ~30 s of
# pure CPU before returning a wrong answer. read_hic_map() called it once per
# tile, so a single screen cost minutes.
#
# R/hic_reader.R replaces that with a stateful reader (one kept-alive
# connection, cached index and blocks), so .hic files no longer need
# downloading. This cache is still used for bigWig / track files, and remains
# available for .hic via hic_engine() == "download".
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
# .hic engine
#   "native"   (default) stateful pure-R reader, R/hic_reader.R. Streams over
#              HTTP range requests on one kept-alive connection; no download.
#   "strawr"   legacy strawr path, remote read directly (slow; see above)
#   "download" legacy strawr path, remote files downloaded to _hic_cache first
#
# Set it from config.txt (key `hic_engine`, exposed in the in-app settings
# dialog) via set_hic_engine(). Precedence, highest first:
#
#   1. HICARTA_HIC_ENGINE environment variable   (scripting / one-off runs)
#   2. options(hicarta.hic_engine = ...)         (R session override)
#   3. set_hic_engine() <- config.txt            (the settings dialog)
#   4. "native"
#
# The native engine falls back to strawr automatically if it cannot parse a
# file, so an unexpected .hic variant degrades instead of breaking.
# ---------------------------------------------------------------------------
HIC_ENGINES <- c("native", "strawr", "download")

.hic_opts <- new.env(parent = emptyenv())
.hic_opts$engine <- NULL

# Apply a choice coming from config.txt / the settings dialog. Returns the
# engine actually in force. Switching drops the cached readers so the next read
# genuinely goes through the new engine.
set_hic_engine <- function(e) {
  e <- tryCatch(tolower(trimws(as.character(e))), error = function(x) "")
  if (length(e) != 1 || is.na(e) || !nzchar(e)) e <- "native"
  if (!(e %in% HIC_ENGINES)) {
    warning("unknown hic_engine '", e, "' - using 'native'", call. = FALSE)
    e <- "native"
  }
  changed <- !identical(.hic_opts$engine, e)
  .hic_opts$engine <- e
  if (changed && exists("hic_forget")) try(hic_forget(), silent = TRUE)
  invisible(hic_engine())
}

hic_engine <- function() {
  pick <- function(x) if (length(x) == 1 && !is.na(x) && nzchar(x)) x else ""
  e <- pick(Sys.getenv("HICARTA_HIC_ENGINE", unset = ""))
  if (!nzchar(e)) e <- pick(as.character(getOption("hicarta.hic_engine", "")))
  if (!nzchar(e)) e <- pick(as.character(.hic_opts$engine))
  if (!nzchar(e) || !(e %in% HIC_ENGINES)) e <- "native"
  e
}

.hic_native <- function() hic_engine() == "native" && exists("hic_reader")

# strawr is OPTIONAL now: it is only the fallback for a .hic the native reader
# cannot parse, and the "strawr"/"download" engines. Guard every use of it so a
# machine without strawr gets a clear message instead of
# "there is no package called 'strawr'".
.have_strawr <- function() requireNamespace("strawr", quietly = TRUE)

.no_strawr <- function(what) {
  stop("cannot ", what, ": the native .hic reader failed and strawr is not ",
       "installed to fall back to.\n",
       "  Install it with  install.packages(\"strawr\")  , or report the file ",
       "so the reader can be fixed.", call. = FALSE)
}

# Path handed to the readers for a given source. The native engine streams the
# URL as-is; only the "download" engine materialises it in _hic_cache first.
hic_source <- function(src) {
  if (hic_engine() == "download") hic_local(src) else src
}

# Metadata accessors. Prefer the native reader: it parses the footer once and
# caches it, and it is the only one that answers correctly for a URL.
hic_resolutions <- function(path) {
  if (.hic_native()) {
    r <- tryCatch(sort(hic_meta(hic_reader(path))$resolutions),
                  error = function(e) NULL)
    if (length(r)) return(r)
  }
  if (!.have_strawr()) .no_strawr("list resolutions")
  sort(strawr::readHicBpResolutions(path))
}

# Resolutions usable for ONE chromosome with ONE normalization.
#
# hic_resolutions() answers from the file header, which is global: a given
# chromosome's matrix can carry fewer zoom levels than the header advertises,
# and a normalization vector can be missing at some of them. Reading at such a
# resolution fails, and in the viewer that is a blank map at the deepest zoom -
# so the zoom ladder must be built from THIS list. Header list as a fallback
# (strawr engine, odd files); never returns empty when the header has something.
hic_resolutions_chr <- function(path, chr, normalization = "NONE", chr2 = chr) {
  if (.hic_native()) {
    r <- tryCatch(hic_chr_resolutions(hic_reader(path), chr, chr2, normalization),
                  error = function(e) NULL)
    if (length(r)) return(sort(r))
  }
  tryCatch(hic_resolutions(path), error = function(e) numeric(0))
}

hic_norms <- function(path) {
  if (.hic_native()) {
    r <- tryCatch(hic_meta(hic_reader(path))$norms, error = function(e) NULL)
    if (length(r)) return(r)
  }
  # Never hand a URL to strawr::readHicNormTypes(): ~30 s CPU, wrong answer.
  if (grepl("^https?://", path)) return("NONE")
  if (!.have_strawr()) return("NONE")
  tryCatch(strawr::readHicNormTypes(path), error = function(e) "NONE")
}

hic_chroms <- function(path) {
  if (.hic_native()) {
    r <- tryCatch(hic_meta(hic_reader(path))$chroms, error = function(e) NULL)
    if (!is.null(r)) return(r)
  }
  if (!.have_strawr()) .no_strawr("list chromosomes")
  strawr::readHicChroms(path)
}

# ---------------------------------------------------------------------------
# 3) .hic (Juicer) via strawr -> sparse (bin1,bin2,counts) -> region matrix
#     path may be a local file OR an https:// URL (strawr streams both).
# ---------------------------------------------------------------------------
read_hic_map <- function(path, chr, start = 1, end = NA, resolution = 10000,
                         normalization = "NONE", unit = "BP",
                         chr2 = NULL, start2 = NULL, end2 = NULL) {
  # No strawr requirement here any more: .hic is read by the native reader
  # (R/hic_reader.R) and strawr is only an optional fallback. Remote files do
  # need curl, though.
  if (grepl("^https?://", path) && !requireNamespace("curl", quietly = TRUE)) {
    stop("Reading a .hic over http(s) needs the 'curl' package. ",
         "Run Rscript R/install_libraries.R", call. = FALSE)
  }
  if (is.null(chr2))   chr2   <- chr
  if (is.null(start2)) start2 <- start
  if (is.null(end2))   end2   <- end
  if (is.na(end))  end  <- .hic_chrom_length(path, chr)
  if (is.na(end2)) end2 <- .hic_chrom_length(path, chr2)

  # Snap to a resolution / normalization that actually exists in this file.
  # (Each menu dataset is a single-resolution file, so asking for the wrong
  #  resolution yields "Error finding block data".)
  # These lookups are cached per file by the native reader, so unlike the old
  # strawr calls they cost nothing after the first tile.
  avail_norm <- tryCatch(hic_norms(path), error = function(e) "NONE")
  if (!(normalization %in% avail_norm)) normalization <- "NONE"
  # Snap to a resolution that exists for THIS chromosome pair under THIS
  # normalization (the header's list is file-global, see hic_resolutions_chr).
  avail_res <- hic_resolutions_chr(path, chr, normalization, chr2)
  if (length(avail_res) && !(resolution %in% avail_res))
    resolution <- avail_res[which.min(abs(avail_res - resolution))]

  d <- .hic_query(path, chr, start, end, chr2, start2, end2,
                  resolution, normalization, unit)
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

# ---------------------------------------------------------------------------
# The actual record query. Native reader first, strawr as a safety net.
# Returns data.frame(x, y, counts) with x/y = bin start positions in bp,
# which is exactly strawr::straw()'s contract.
# ---------------------------------------------------------------------------
.hic_query <- function(path, chr, start, end, chr2, start2, end2,
                       resolution, normalization, unit) {
  if (.hic_native()) {
    out <- tryCatch(
      hic_records(hic_reader(path), chr, start, end, chr2, start2, end2,
                  resolution = resolution, normalization = normalization,
                  unit = unit),
      error = function(e) {
        message("[hic] native reader failed (", conditionMessage(e),
                ") - falling back to strawr for ", basename(path))
        NULL
      })
    if (!is.null(out)) return(out)
  }
  if (!.have_strawr()) .no_strawr(sprintf("read %s", basename(path)))
  p <- if (hic_engine() == "download") hic_local(path) else path
  strawr::straw(normalization, p,
                sprintf("%s:%.0f:%.0f", chr,  start,  end),
                sprintf("%s:%.0f:%.0f", chr2, start2, end2),
                unit, resolution)
}

.hic_chrom_length <- function(path, chr) {
  info <- hic_chroms(path)
  as.numeric(info$length[info$name == chr])
}

# List chromosomes & resolutions available in a .hic (for the UI).
hic_metadata <- function(path) {
  list(
    chroms      = hic_chroms(path),
    resolutions = hic_resolutions(path),
    norms       = tryCatch(hic_norms(path), error = function(e) c("NONE"))
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
