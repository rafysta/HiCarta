#!/usr/bin/env Rscript
# ============================================================================
# test_bigwig_reader.R  -  acceptance test for R/bigwig_reader.R
#
# Verifies the pure-R streaming bigWig reader against rtracklayer (the
# reference implementation) and benchmarks it.
#
# USAGE
#   Rscript scripts/test_bigwig_reader.R <file-or-url> [<file-or-url> ...]
#
# NOTE ON REMOTE FILES
#   rtracklayer cannot open a bigWig over http(s) at all ("Couldn't open ...
#   UCSC library operation failed"), which is precisely why this reader exists.
#   So for a URL only the self-consistency checks run. To validate a remote
#   file properly, pass BOTH the URL and a local copy of the same file: the
#   script then also checks that the two agree exactly.
#
# WHAT IT CHECKS
#   A) chromosome names and lengths match rtracklayer's seqinfo
#   B) bw_intervals() matches rtracklayer::import(which=) exactly, including
#      the clipping of edge intervals to the query window
#   C) bw_summary()'s full-resolution path matches an independent overlap
#      binning of import() -- exact, and independent of Kent's zoom machinery
#   D) bw_summary()'s zoom path matches rtracklayer::summary() exactly, i.e.
#      the zoom aggregation follows Kent's. (Zoom answers legitimately differ
#      from full-resolution ones: a zoom record's max leaks into every bin it
#      touches. The reader prefers full resolution when the data is small
#      enough, which is exact and therefore better.)
#   E) local vs remote agreement, and I/O counters
#
# Exit status is non-zero if any comparison fails.
# ============================================================================

here <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=",
          commandArgs(FALSE), value = TRUE)[1]))), error = function(e) ".")
src <- file.path(here, "..", "R", "bigwig_reader.R")
if (!file.exists(src)) src <- "R/bigwig_reader.R"
source(src)

have_rtl <- requireNamespace("rtracklayer", quietly = TRUE) &&
            requireNamespace("GenomicRanges", quietly = TRUE)
if (have_rtl) suppressMessages({
  library(rtracklayer); library(GenomicRanges); library(IRanges)
}) else cat("NOTE: rtracklayer not installed - self-checks only.\n\n")

args <- commandArgs(TRUE)
if (!length(args)) stop("give at least one bigWig file or URL")

PASS <- 0L; FAIL <- 0L; NOTES <- character(0)
chk <- function(ok, lab, extra = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %s\n", lab)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s  %s\n", lab, extra))
         NOTES <<- c(NOTES, lab) }
}
relmax <- function(a, b) {
  if (length(a) != length(b)) return(Inf)
  if (!length(a)) return(0)
  max(abs(a - b) / pmax(1e-9, abs(b)))
}

readers <- list()

for (path in args) {
  cat("\n==================================================================\n")
  cat(path, "\n==================================================================\n")
  rd <- tryCatch(bw_open(path), error = function(e) {
    cat("  cannot open:", conditionMessage(e), "\n"); NULL })
  if (is.null(rd)) { FAIL <- FAIL + 1L; next }
  readers[[path]] <- rd
  ch <- bw_chroms(rd)
  cat(sprintf("  version %d  %s-endian  zoomLevels=%d  compressed=%s  chroms=%d\n",
              rd$version, if (rd$big) "big" else "little", rd$zoomLevels,
              rd$uncompressBufSize > 0, nrow(ch)))
  ts <- bw_total_summary(rd)
  if (!is.null(ts))
    cat(sprintf("  coverage %.0f bases, value range %.4g .. %.4g\n",
                ts$validCount, ts$min, ts$max))

  local_file <- !grepl("^https?://", path)
  CH <- ch$name[which.max(ch$size)]
  L  <- ch$size[which.max(ch$size)]
  cat(sprintf("  testing on %s (%.0f bp)\n", CH, L))

  if (have_rtl && local_file) {
    cat("\n  A) chromosomes vs rtracklayer\n")
    si <- tryCatch(seqinfo(BigWigFile(path)), error = function(e) NULL)
    if (!is.null(si)) {
      chk(setequal(as.character(seqnames(si)), ch$name), "names match")
      chk(all(as.numeric(seqlengths(si)[ch$name]) == ch$size), "lengths match")
    }

    cat("\n  B) bw_intervals() vs rtracklayer::import()  [exact]\n")
    regs <- list(c(1, 1), c(99, 99), c(1, 10000), c(150, 650),
                 c(round(L/4), round(L/4) + 50000),
                 c(max(1, L - 2000), L), c(1, L), c(L, L + 100000))
    for (r in regs) {
      gr  <- GRanges(CH, IRanges(r[1], r[2]))
      ref <- tryCatch(import(path, which = gr), error = function(e) NULL)
      got <- bw_intervals(rd, CH, r[1], r[2])
      rs <- if (is.null(ref)) numeric(0) else start(ref)
      re <- if (is.null(ref)) numeric(0) else end(ref)
      rv <- if (is.null(ref)) numeric(0) else as.numeric(score(ref))
      o <- order(rs, re); rs <- rs[o]; re <- re[o]; rv <- rv[o]
      chk(nrow(got) == length(rs) && all(got$start == rs) &&
            all(got$end == re) && (!length(rs) || max(abs(got$value - rv)) < 1e-6),
          sprintf("%s:%.0f-%.0f  n=%d", CH, r[1], r[2], nrow(got)),
          sprintf("(rtracklayer n=%d)", length(rs)))
    }

    cat("\n  C) bw_summary() full-resolution vs independent binning  [exact]\n")
    indep <- function(s, e, nb, type) {
      g  <- import(path, which = GRanges(CH, IRanges(s, e)))
      ed <- seq(s - 1, e, length.out = nb + 1); val <- rep(0, nb)
      st <- start(g) - 1; en <- end(g); sv <- as.numeric(score(g))
      for (i in seq_len(nb)) {
        lo <- ed[i]; hi <- ed[i + 1]
        w <- pmin(en, hi) - pmax(st, lo); w[w < 0] <- 0
        if (type == "max") { k <- which(w > 0)
          val[i] <- if (length(k)) max(sv[k]) else 0
        } else val[i] <- if (sum(w) > 0) sum(sv * w) / sum(w) else 0
      }
      val
    }
    for (r in list(c(1, min(1e5, L)), c(1, min(1e6, L)), c(1, L)))
      for (nb in c(10, 137, 500)) for (ty in c("mean", "max")) {
        a <- bw_summary(rd, CH, r[1], r[2], nb, ty)
        b <- indep(r[1], r[2], nb, ty)
        rr <- relmax(a, b)
        chk(rr < 1e-6, sprintf("%s:%.0f-%.0f nbins=%d %s (maxrel=%.1e)",
                               CH, r[1], r[2], nb, ty, rr))
      }

    cat("\n  D) bw_summary() zoom path vs rtracklayer::summary()  [exact]\n")
    bwf <- BigWigFile(path)
    for (r in list(c(1, min(1e6, L)), c(1, L))) for (nb in c(20, 50, 200))
      for (ty in c("mean", "max")) {
        ref <- tryCatch(as.numeric(score(rtracklayer::summary(
                 bwf, which = GRanges(CH, IRanges(r[1], r[2])),
                 size = nb, type = ty, defaultValue = 0)[[1]])),
                 error = function(e) NULL)
        if (is.null(ref)) next
        got <- bw_summary(rd, CH, r[1], r[2], nb, ty, max_full_bytes = 0)
        rr  <- relmax(got, ref)
        chk(rr < 1e-5, sprintf("%s:%.0f-%.0f nbins=%d %s (maxrel=%.1e)",
                               CH, r[1], r[2], nb, ty, rr))
      }
  } else if (have_rtl && !local_file) {
    cat("\n  (rtracklayer cannot open remote bigWig - comparison skipped)\n")
  }

  cat("\n  E) benchmark - 200-bin track over the whole chromosome\n")
  rd2 <- bw_open(path)
  t1 <- system.time(v1 <- bw_summary(rd2, CH, 1, L, 200, "mean"))[["elapsed"]]
  io <- bw_io_stats(rd2)
  t2 <- system.time(bw_summary(rd2, CH, 1, L, 200, "mean"))[["elapsed"]]
  cat(sprintf("    cold %.3f s (%d range reads, %.2f MB)   warm %.3f s (+%d reads)\n",
              t1, io$reads, io$bytes / 1024^2, t2,
              bw_io_stats(rd2)$reads - io$reads))
  chk(length(v1) == 200 && all(is.finite(v1)), "summary is finite and complete")
  bw_close(rd2)
}

# ---- cross-check: same file given both as a local path and as a URL --------
locs <- names(readers)[!grepl("^https?://", names(readers))]
urls <- names(readers)[grepl("^https?://", names(readers))]
if (length(locs) && length(urls)) {
  cat("\n==================================================================\n")
  cat("F) local vs remote agreement\n==================================================================\n")
  for (u in urls) {
    b <- basename(sub("\\?.*$", "", u))
    m <- locs[basename(locs) == b]
    if (!length(m)) next
    rl <- readers[[m[1]]]; rr <- readers[[u]]
    ch <- bw_chroms(rl); CH <- ch$name[which.max(ch$size)]
    L  <- ch$size[which.max(ch$size)]
    chk(identical(bw_chroms(rl), bw_chroms(rr)), sprintf("%s: chromosomes", b))
    a <- bw_intervals(rl, CH, 1, min(2e5, L))
    d <- bw_intervals(rr, CH, 1, min(2e5, L))
    chk(identical(dim(a), dim(d)) && isTRUE(all.equal(a, d)),
        sprintf("%s: intervals identical (n=%d)", b, nrow(a)))
    for (ty in c("mean", "max")) {
      s1 <- bw_summary(rl, CH, 1, L, 300, ty)
      s2 <- bw_summary(rr, CH, 1, L, 300, ty)
      chk(isTRUE(all.equal(s1, s2)), sprintf("%s: summary %s identical", b, ty))
    }
  }
}

for (rd in readers) try(bw_close(rd), silent = TRUE)

cat("\n==================================================================\n")
cat(sprintf("TOTAL: %d passed, %d failed\n", PASS, FAIL))
if (FAIL) {
  cat("failing checks:\n"); cat(paste0("  - ", unique(NOTES), collapse = "\n"), "\n")
  quit(status = 1)
}
cat("all checks passed\n")
