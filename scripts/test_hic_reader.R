#!/usr/bin/env Rscript
# ============================================================================
# test_hic_reader.R  -  acceptance test for R/hic_reader.R
#
# Verifies the pure-R stateful .hic reader against strawr (the reference
# implementation) and benchmarks both on a Leaflet-tile-shaped access pattern.
#
# USAGE
#   Rscript scripts/test_hic_reader.R  <file-or-url> [<file-or-url> ...]
#
#   # local file
#   Rscript scripts/test_hic_reader.R _hic_cache/wt_HiC_ICE.10kb.hic
#   # remote URL (this is the case that matters)
#   Rscript scripts/test_hic_reader.R https://host/path/wt_ICE.10kb.hic
#
# With no arguments it looks for .hic files in _hic_cache/.
#
# WHAT IT CHECKS
#   A) metadata (chromosomes, resolutions, normalizations) matches strawr
#   B) records match strawr exactly over a grid of regions x resolutions x
#      normalizations, including inter-chromosomal and asymmetric windows
#   C) wall-clock and I/O for ~20 tile-sized queries, reader vs strawr
#
# Exit status is non-zero if any comparison fails.
# ============================================================================

suppressWarnings(suppressMessages({
  here <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=",
            commandArgs(FALSE), value = TRUE)[1]))), error = function(e) ".")
}))
src <- file.path(here, "..", "R", "hic_reader.R")
if (!file.exists(src)) src <- "R/hic_reader.R"
source(src)

have_strawr <- requireNamespace("strawr", quietly = TRUE)
if (!have_strawr)
  cat("NOTE: strawr is not installed - skipping comparison, running self-checks only.\n\n")

args <- commandArgs(TRUE)
if (!length(args)) {
  args <- Sys.glob(file.path(here, "..", "_hic_cache", "*.hic"))
  if (!length(args)) args <- Sys.glob("_hic_cache/*.hic")
}
if (!length(args)) stop("give at least one .hic file or URL")

PASS <- 0L; FAIL <- 0L; NOTES <- character(0)
chk <- function(ok, label, extra = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %s\n", label)) }
  else { FAIL <<- FAIL + 1L
         cat(sprintf("  [FAIL] %s  %s\n", label, extra))
         NOTES <<- c(NOTES, label) }
}

# NaN-tolerant numeric comparison (normalization vectors legitimately hold NaN)
same_counts <- function(a, b, tol = 1e-5) {
  if (length(a) != length(b)) return(FALSE)
  if (!length(a)) return(TRUE)
  bothna <- is.na(a) & is.na(b)
  rel <- abs(a - b) / pmax(1e-12, abs(b))
  all(bothna | (!is.na(rel) & rel < tol))
}
canon <- function(df) df[order(df$x, df$y, df$counts), , drop = FALSE]

for (path in args) {
  cat("\n==================================================================\n")
  cat(path, "\n")
  cat("==================================================================\n")

  rd <- tryCatch(hic_open(path), error = function(e) {
    cat("  cannot open:", conditionMessage(e), "\n"); NULL })
  if (is.null(rd)) { FAIL <- FAIL + 1L; next }
  m <- hic_meta(rd)
  cat(sprintf("  v%d  genome=%s  chroms=%d  resolutions=%s  norms=%s\n",
              m$version, m$genomeId, nrow(m$chroms),
              paste(m$resolutions, collapse = ","),
              paste(m$norms, collapse = ",")))

  # ---- A) metadata vs strawr --------------------------------------------
  if (have_strawr) {
    cat("\n  A) metadata\n")
    sc <- tryCatch(strawr::readHicChroms(path), error = function(e) NULL)
    if (!is.null(sc)) {
      chk(setequal(as.character(sc$name), as.character(m$chroms$name)),
          "chromosome names match strawr")
      i <- match(as.character(sc$name), as.character(m$chroms$name))
      chk(all(as.numeric(sc$length) == as.numeric(m$chroms$length[i])),
          "chromosome lengths match strawr")
    }
    sr <- tryCatch(strawr::readHicBpResolutions(path), error = function(e) NULL)
    if (!is.null(sr))
      chk(setequal(as.numeric(sr), as.numeric(m$resolutions)),
          "resolutions match strawr")
    sn <- tryCatch(strawr::readHicNormTypes(path), error = function(e) NULL)
    if (!is.null(sn))
      chk(all(as.character(sn) %in% m$norms),
          "strawr normalizations are all offered by the reader",
          paste("strawr:", paste(sn, collapse = ","),
                "reader:", paste(m$norms, collapse = ",")))
  }

  # ---- self-check: the file's own sumCounts checksum --------------------
  # For an intra matrix the writer counts off-diagonal cells twice but stores
  # them once, so  sumCounts == 2*sum(stored) - sum(diagonal).
  cat("\n  B) internal checksum (file's own sumCounts field)\n")
  # Drop the genome-wide aggregate pseudo-chromosome. Its name is spelled
  # "All" by some writers and "ALL" by others, and it carries its own
  # resolutions, so match case-insensitively.
  chroms <- m$chroms[!toupper(m$chroms$name) %in% "ALL", , drop = FALSE]
  for (res in m$resolutions) {
    for (k in seq_len(nrow(chroms))) {
      nm <- chroms$name[k]; len <- chroms$length[k]
      bi <- tryCatch(.hic_block_index(rd, chroms$index[k], chroms$index[k],
                                      "BP", res), error = function(e) NULL)
      if (is.null(bi)) next
      # start at 0, not 1: bin 0 spans bp 0 and would be filtered out by the
      # >= start test (strawr behaves the same way), which at coarse
      # resolutions removes a large slice of the matrix.
      r <- tryCatch(hic_records(rd, nm, 0, len, resolution = res),
                    error = function(e) NULL)
      if (is.null(r) || !nrow(r)) next
      stored <- sum(r$counts)
      diag_  <- sum(r$counts[r$x == r$y])
      pred   <- 2 * stored - diag_
      chk(abs(pred - bi$sumCounts) / bi$sumCounts < 1e-5,
          sprintf("checksum %s @%s", nm, format(res, scientific = FALSE)),
          sprintf("predicted %.1f vs file %.1f", pred, bi$sumCounts))
    }
  }

  # ---- C) records vs strawr --------------------------------------------
  if (have_strawr) {
    cat("\n  C) records vs strawr\n")
    c1 <- chroms$name[1]
    L1 <- chroms$length[1]
    c2 <- if (nrow(chroms) > 1) chroms$name[2] else c1
    L2 <- if (nrow(chroms) > 1) chroms$length[2] else L1
    norms <- intersect(m$norms, c("NONE", "KR", "VC", "VC_SQRT", "SCALE"))
    for (res in m$resolutions) for (nn in norms) {
      # Windows must be sized in BINS, not in bp: a 1 Mb window is meaningless
      # at 2.5 Mb resolution. 60 bins is a realistic on-screen span.
      W  <- min(60 * res, L1)
      Wb <- min(60 * res, L2)
      wins <- list(
        list(c1, 1, W, c1, 1, W),                              # small intra
        list(c1, 1, L1, c1, 1, L1),                            # whole chromosome
        list(c1, 1, min(20 * res, L1),                         # off-diagonal
             c1, min(30 * res, L1), min(50 * res, L1)),
        list(c1, 1, W, c2, 1, Wb)                              # inter-chromosomal
      )
      for (w in wins) {
      lab <- sprintf("%s:%.0f-%.0f x %s:%.0f-%.0f @%s %s",
                     w[[1]], w[[2]], w[[3]], w[[4]], w[[5]], w[[6]],
                     format(res, scientific = FALSE), nn)
      ref <- tryCatch(strawr::straw(nn, path,
                       sprintf("%s:%.0f:%.0f", w[[1]], w[[2]], w[[3]]),
                       sprintf("%s:%.0f:%.0f", w[[4]], w[[5]], w[[6]]),
                       "BP", res), error = function(e) NULL)
      if (is.null(ref)) next
      got <- tryCatch(hic_records(rd, w[[1]], w[[2]], w[[3]], w[[4]], w[[5]],
                                  w[[6]], resolution = res,
                                  normalization = nn),
                      error = function(e) NULL)
      if (is.null(got)) { chk(FALSE, lab, "reader errored"); next }
      a <- canon(got); b <- canon(as.data.frame(ref))
      chk(nrow(a) == nrow(b) && all(a$x == b$x) && all(a$y == b$y) &&
            same_counts(a$counts, b$counts), lab,
          sprintf("reader n=%d strawr n=%d", nrow(a), nrow(b)))
      }
    }
  }

  # ---- D) benchmark: a screen of Leaflet tiles ---------------------------
  cat("\n  D) benchmark - 20 tile-sized queries (one screen)\n")
  res <- m$resolutions[which.min(abs(m$resolutions - 10000))]
  nm  <- chroms$name[1]; L <- chroms$length[1]
  span <- min(100 * res, L)          # ~100 bins across, sized to the resolution
  edges <- seq(1, span, length.out = 6)
  tiles <- list()
  for (i in 1:5) for (j in 1:4)
    tiles[[length(tiles) + 1L]] <- c(edges[i], edges[i + 1], edges[j], edges[j + 1])

  rd2 <- hic_open(path)                       # cold reader, fair comparison
  t_rd <- system.time({
    for (t in tiles)
      hic_records(rd2, nm, t[1], t[2], nm, t[3], t[4], resolution = res)
  })[["elapsed"]]
  io <- hic_io_stats(rd2)
  cat(sprintf("    reader : %6.2f s   range reads=%d   bytes=%.2f MB\n",
              t_rd, io$reads, io$bytes / 1024^2))

  if (have_strawr) {
    t_sw <- tryCatch(system.time({
      for (t in tiles) {
        # replicate what read_hic_map() does per tile today
        strawr::readHicBpResolutions(path)
        try(strawr::readHicNormTypes(path), silent = TRUE)
        strawr::straw("NONE", path,
                      sprintf("%s:%.0f:%.0f", nm, t[1], t[2]),
                      sprintf("%s:%.0f:%.0f", nm, t[3], t[4]), "BP", res)
      }
    })[["elapsed"]], error = function(e) NA_real_)
    cat(sprintf("    strawr : %6.2f s   (4 file opens per tile)\n", t_sw))
    if (!is.na(t_sw) && t_rd > 0)
      cat(sprintf("    speedup: %.1fx\n", t_sw / t_rd))
  }
  hic_close(rd2); hic_close(rd)
}

cat("\n==================================================================\n")
cat(sprintf("TOTAL: %d passed, %d failed\n", PASS, FAIL))
if (FAIL) {
  cat("failing checks:\n"); cat(paste0("  - ", unique(NOTES), collapse = "\n"), "\n")
  quit(status = 1)
}
cat("all checks passed\n")
