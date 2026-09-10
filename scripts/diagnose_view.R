#!/usr/bin/env Rscript
# ============================================================================
# diagnose_view.R  -  why does THIS view look wrong?
#
# Replays, outside Shiny, exactly what HiCarta does to paint one view:
#   the reader's own view of the file, the overview read that seeds the colour
#   scale, the value scale the app derives from it, the tile read for the
#   region you are looking at, the normalization vector behind it, and the
#   effective colour limits after the (res/vref)^2 correction.
#
# It answers the question the screen cannot: is the map flat because the DATA
# came back empty / zero / NaN, or because the colour LIMITS are far from it?
#
# USAGE (run from the HiCarta folder)
#   Rscript scripts/diagnose_view.R <file.hic> [chr] [xstart] [xend] \
#           [ystart] [yend] [resolution] [normalization]
#
#   # metadata only - no region needed
#   Rscript scripts/diagnose_view.R "E:/.../IMR90_G_bmix_KR.hic"
#
#   # a specific view
#   Rscript scripts/diagnose_view.R "E:/.../IMR90_G_bmix_KR.hic" chr4 \
#           65980000 79970000 69000000 76480000 10000 KR
#
# QUOTE THE PATH. An unquoted Windows path with backslashes loses them, and
# the script then reports the file as missing.
# ============================================================================

suppressWarnings(suppressMessages({
  here <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=",
            commandArgs(FALSE), value = TRUE)[1]))), error = function(e) ".")
}))
src <- function(f) {
  p <- file.path(here, "..", "R", f)
  if (!file.exists(p)) p <- file.path("R", f)
  if (!file.exists(p)) stop("cannot find R/", f, " - run this from the HiCarta folder")
  source(p)
}
src("hic_reader.R"); src("readers.R"); src("tiles.R")

a <- commandArgs(TRUE)
if (length(a) < 1) {
  cat("usage: Rscript scripts/diagnose_view.R \"<file.hic>\" [chr xstart xend",
      "ystart yend resolution normalization]\n")
  quit(status = 1)
}
path     <- a[1]
chr      <- if (length(a) >= 2) a[2] else NA_character_
x0       <- if (length(a) >= 3) as.numeric(a[3]) else NA_real_
x1       <- if (length(a) >= 4) as.numeric(a[4]) else NA_real_
y0       <- if (length(a) >= 5) as.numeric(a[5]) else x0
y1       <- if (length(a) >= 6) as.numeric(a[6]) else x1
res_want <- if (length(a) >= 7) as.numeric(a[7]) else 10000
norm     <- if (length(a) >= 8) a[8] else "KR"
do_region <- !is.na(chr) && is.finite(x0) && is.finite(x1)

hr  <- function(t) cat("\n== ", t, " ", strrep("=", max(0, 66 - nchar(t))), "\n", sep = "")
num <- function(v) format(v, big.mark = ",", scientific = FALSE)

# ---------------------------------------------------------------------------
# 0) the path. A wrong path is by far the most common reason this script fails,
#    and R gives no hint about WHY, so spell it out before anything else.
# ---------------------------------------------------------------------------
hr("file")
cat("argument as R received it:\n  ", path, "\n", sep = "")
if (!file.exists(path)) {
  cat("\n!! file.exists() says NO.\n")
  alt <- gsub("\\\\", "/", path)
  if (alt != path && file.exists(alt)) {
    cat("   ...but it exists with forward slashes. Using that.\n")
    path <- alt
  } else {
    dir <- dirname(path)
    cat("   parent folder : ", dir, "\n", sep = "")
    cat("   folder exists : ", dir.exists(dir), "\n", sep = "")
    if (dir.exists(dir)) {
      hs <- list.files(dir, pattern = "\\.hic$", ignore.case = TRUE)
      cat("   .hic files actually in it:\n")
      if (length(hs)) cat(paste0("     ", hs, collapse = "\n"), "\n", sep = "")
      else cat("     (none - the .hic files may be in a subfolder)\n")
    }
    cat("\n   Most likely: the path was pasted unquoted and the shell ate the\n",
        "   backslashes. Wrap it in double quotes, or use forward slashes.\n", sep = "")
    quit(status = 1)
  }
}
cat("size : ", num(file.info(path)$size), " bytes (",
    round(file.info(path)$size / 1024^3, 2), " GB)\n", sep = "")

# ---------------------------------------------------------------------------
# 1) what the reader itself sees. Version, where the footer starts, and how big
#    the footer tail is - a large tail is read in a bounded chunk first, so it
#    is worth knowing whether that shortcut applied to this file.
# ---------------------------------------------------------------------------
hr("reader metadata")
rd <- hic_reader(path)
cat("hic version   : ", rd$version, "   (v9 layout: ", rd$v9, ")\n", sep = "")
cat("genome id     : ", rd$genomeId, "\n", sep = "")
cat("master offset : ", num(rd$master), "\n", sep = "")
tail_len <- rd$size - rd$master
cat("footer tail   : ", num(tail_len), " bytes",
    if (tail_len > 8 * 1024^2) "  (larger than the 8 MB pre-read)" else "", "\n", sep = "")
cat("header resolutions:\n  ", paste(rd$resolutions, collapse = ", "), "\n", sep = "")
ft <- .hic_read_footer(rd)
cat("footer: matrices=", num(length(ft$matrixIndex)),
    "  expected-value vectors=", num(length(ft$expected)),
    "  normalization vectors=", num(length(ft$normIndex)), "\n", sep = "")
nm <- tryCatch(hic_norms(path), error = function(e) character(0))
cat("normalizations: ", paste(nm, collapse = ", "), "\n", sep = "")

ci <- hic_chroms(path)
cat("chromosomes   : ", nrow(ci), "\n", sep = "")
if (!do_region) {
  cat("\n(no region given - stopping after metadata)\n")
  quit(status = 0)
}

i <- match(tolower(chr), tolower(as.character(ci$name)))
if (is.na(i)) i <- match(tolower(sub("^chr", "", chr)),
                         tolower(sub("^chr", "", as.character(ci$name))))
if (is.na(i)) stop("chromosome ", chr, " is not in this file: ",
                   paste(ci$name, collapse = ", "))
chr    <- as.character(ci$name)[i]
chrlen <- as.numeric(ci$length)[i]
cat("target chrom  : ", chr, "  length ", num(chrlen), " bp\n", sep = "")

# ---------------------------------------------------------------------------
# 2) which resolutions this chromosome really offers under this normalization
# ---------------------------------------------------------------------------
hr("resolutions for this chromosome")
if (!(norm %in% nm))
  cat("!! '", norm, "' is NOT offered by this file - reads fall back to NONE\n", sep = "")
res_raw <- hic_resolutions_chr(path, chr, "NONE", chr)
res_all <- hic_resolutions_chr(path, chr, norm, chr)
cat("under NONE : ", paste(res_raw, collapse = ", "), "\n", sep = "")
cat("under ", norm, " : ", paste(res_all, collapse = ", "), "\n", sep = "")
lost <- setdiff(res_raw, res_all)
if (length(lost))
  cat("   (dropped for lack of a ", norm, " vector: ",
      paste(lost, collapse = ", "), ")\n", sep = "")
if (!length(res_all)) stop("no usable resolution")
res <- res_all[which.min(abs(log2(res_all) - log2(res_want)))]
if (res != res_want)
  cat("!! ", num(res_want), " is not available - snapped to ", num(res), "\n", sep = "")

# ---------------------------------------------------------------------------
# 3) the normalization vector behind the picture. THE decisive number.
#    hic_records() does  cnt <- v / (n1[x] * n2[y]) : one NaN entry turns a
#    perfectly good contact into NaN, and values_to_colors() draws NaN
#    TRANSPARENT (= white). Bins with no record at all stay 0, and 0 is the
#    BOTTOM of the palette - dark navy in both 'matlab' and 'gentle'.
#    White on solid blue, unmoved by the max slider or the palette, is exactly
#    that pair of states.
# ---------------------------------------------------------------------------
hr("normalization vector")
ovres <- choose_res(chrlen / 400, res_all)
for (rr in unique(c(res, ovres))) {
  nv <- tryCatch(.hic_norm_vector(rd, norm, .hic_chr_index(rd, chr), "BP", rr),
                 error = function(e) { cat(sprintf("%-4s @ %-8s : MISSING (%s)\n",
                     norm, fmt_res(rr), conditionMessage(e))); NULL })
  if (is.null(nv)) next
  need <- ceiling(chrlen / rr)
  cat(sprintf("%-4s @ %-8s : length=%s (chromosome needs %s)  NaN/NA=%s (%.1f%%)  <=0=%s\n",
              norm, fmt_res(rr), num(length(nv)), num(need),
              num(sum(!is.finite(nv))), 100 * mean(!is.finite(nv)),
              num(sum(nv <= 0, na.rm = TRUE))))
  b0 <- max(1, floor(min(x0, y0) / rr) + 1)
  b1 <- min(length(nv), ceiling(max(x1, y1) / rr))
  if (b1 >= b0) {
    sub <- nv[b0:b1]
    cat(sprintf("       in this region: bins %s..%s  NaN/NA=%s (%.1f%%)  median=%.4g\n",
                num(b0), num(b1), num(sum(!is.finite(sub))),
                100 * mean(!is.finite(sub)),
                suppressWarnings(stats::median(sub[is.finite(sub)]))))
  }
}

# ---------------------------------------------------------------------------
# 4) the reads themselves
# ---------------------------------------------------------------------------
stats <- function(v, label) {
  v <- as.numeric(v); n <- length(v)
  nna <- sum(is.na(v)); fin <- v[is.finite(v)]
  cat(sprintf("%-24s n=%s  NA/NaN=%s (%.1f%%)  zero=%s (%.1f%%)  neg=%s\n",
              label, num(n), num(nna), 100 * nna / max(1, n),
              num(sum(fin == 0)), 100 * sum(fin == 0) / max(1, length(fin)),
              num(sum(fin < 0))))
  if (!length(fin)) { cat("                         (no finite values at all)\n"); return(numeric(0)) }
  q <- stats::quantile(fin, c(0, .5, .9, .99, 1), names = FALSE)
  cat(sprintf("                         min=%.4g median=%.4g p90=%.4g p99=%.4g max=%.4g\n",
              q[1], q[2], q[3], q[4], q[5]))
  fin
}
auto_vmax <- function(vals) {          # app.R's own rule
  q <- function(v, p) if (length(v)) sort(v)[max(1, round(length(v) * p))] else NA_real_
  v99 <- q(vals, 0.99); if (is.finite(v99) && v99 > 0) return(v99)
  p99 <- q(vals[vals > 0], 0.99); if (is.finite(p99) && p99 > 0) return(p99)
  mx <- suppressWarnings(max(vals, na.rm = TRUE)); if (is.finite(mx) && mx > 0) mx else 1
}
timed <- function(expr) {
  t0 <- Sys.time(); v <- force(expr)
  cat("   (", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), " s)\n", sep = "")
  v
}

hr("overview read (this seeds the colour scale)")
cat("overview resolution (app: chrlen/400) : ", fmt_res(ovres), "\n", sep = "")
ov <- timed(read_hic_map(path, chr = chr, start = 1, end = NA,
                         resolution = ovres, normalization = norm,
                         chr2 = chr, start2 = 1, end2 = NA))
cat("matrix ", nrow(ov), " x ", ncol(ov), "\n", sep = "")
ovfin <- stats(ov, "overview values")
p99 <- auto_vmax(ovfin)
cat(sprintf("\napp's automatic max (p99 of the overview) : %.6g\n", p99))

hr("the region you are looking at")
cat("x (columns): ", chr, ":", num(x0), "-", num(x1), "\n", sep = "")
cat("y (rows)   : ", chr, ":", num(y0), "-", num(y1), "\n", sep = "")
cat("resolution : ", fmt_res(res), "\n", sep = "")
m <- tryCatch(timed(read_hic_map(path, chr = chr, start = y0, end = y1,
                                 resolution = res, normalization = norm,
                                 chr2 = chr, start2 = x0, end2 = x1)),
              error = function(e) { cat("!! READ FAILED: ", conditionMessage(e), "\n", sep = ""); NULL })
if (is.null(m)) quit(status = 2)
cat("matrix ", nrow(m), " x ", ncol(m), "\n", sep = "")
mfin <- stats(m, paste0("region @ ", norm))

d <- tryCatch(hic_records(rd, chr, y0, y1, chr, x0, x1,
                          resolution = res, normalization = norm),
              error = function(e) NULL)
cat("raw records from the reader : ",
    if (is.null(d)) "READ FAILED" else num(nrow(d)), "\n", sep = "")
if (!is.null(d) && nrow(d))
  cat(sprintf("   of those: NaN=%s  zero=%s  negative=%s  max=%.6g\n",
              num(sum(is.na(d$counts))), num(sum(d$counts == 0, na.rm = TRUE)),
              num(sum(d$counts < 0, na.rm = TRUE)),
              suppressWarnings(max(d$counts, na.rm = TRUE))))

# the same region unnormalized separates "no data here" from
# "the normalization vector destroyed the data"
mr <- tryCatch(read_hic_map(path, chr = chr, start = y0, end = y1,
                            resolution = res, normalization = "NONE",
                            chr2 = chr, start2 = x0, end2 = x1),
               error = function(e) NULL)
if (!is.null(mr)) stats(mr, "same region, RAW")

# ---------------------------------------------------------------------------
# 5) what the screen does with that
# ---------------------------------------------------------------------------
hr("what the screen would do with it")
cat("render_tile(): f <- (res/vref)^2 ; values_to_colors(val, colour, vmin*f, vmax*f)\n\n")
for (vref in sort(unique(c(ovres, res_all)))) {
  f <- (res / vref)^2
  eff <- p99 * f
  above <- if (length(mfin)) 100 * mean(mfin >= eff) else NA
  below <- if (length(mfin)) 100 * mean(mfin <= eff / 255) else NA
  cat(sprintf("vref=%-9s f=%-11.4g effective max=%-12.6g %6.1f%% saturate %6.1f%% bottom 1/255\n",
              fmt_res(vref), f, eff, above, below))
}
cat("\nHow to read this:\n")
cat("  'saturate' near 100%      -> the map sits at the TOP of the palette (dark red)\n")
cat("  'bottom 1/255' near 100%  -> the map sits at the BOTTOM (dark navy in matlab\n")
cat("                               and gentle alike), with NaN pixels transparent\n")
cat("                               = white. Blue + white and nothing else is that.\n")
cat("The row that matters is the vref of the chromosome the dataset was FIRST\n")
cat("opened on - that is what st$vref holds while you navigate.\n")

hr("done")
