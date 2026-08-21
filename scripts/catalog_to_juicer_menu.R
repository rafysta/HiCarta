#!/usr/bin/env Rscript
# ============================================================================
# catalog_to_juicer_menu.R - export the Hi-C rows of an Excel data catalog
# back to a legacy Juicer-style menu file.
#
# Usage:
#   Rscript scripts/catalog_to_juicer_menu.R CATALOG.xlsx MENU.txt
#
# Every valid catalog row whose file_type is "hic" becomes one sample group;
# each of its ";"-separated path entries becomes one dataset line:
#   s<id>   = root, <name>
#   s<id>_1 = s<id>, <label or file name>, <url>
#
# Run from the HiCarta folder (the script sources R/i18n.R and R/catalog.R).
# Requires: readxl  (already required by HiCarta itself)
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  cat("Usage: Rscript scripts/catalog_to_juicer_menu.R CATALOG.xlsx MENU.txt\n")
  quit(status = 1)
}
cat_file <- args[1]; out_file <- args[2]

script_dir <- tryCatch({
  f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  dirname(normalizePath(sub("^--file=", "", f[1])))
}, error = function(e) "scripts")
app_dir <- dirname(script_dir)
source(file.path(app_dir, "R", "i18n.R"))     # tr() used by catalog messages
source(file.path(app_dir, "R", "catalog.R"))

cc <- read_catalog(cat_file)
if (!isTRUE(cc$ok)) stop("could not read catalog: ", cc$fatal)
if (nrow(cc$errors) > 0)
  cat(sprintf("Note: %d broken row(s) were excluded (open the catalog in HiCarta to see why).\n",
              nrow(cc$errors)))

is_hic <- !is.na(cc$file_type) & cc$file_type == "hic"
if (!any(is_hic)) stop("the catalog has no valid Hi-C (file_type = hic) rows")

names_col <- cc$data[[which(tolower(trimws(names(cc$data))) == "name")[1]]]
lines <- c("# Juicer-style sample menu exported from an Excel data catalog",
           sprintf("# source: %s  (%s)", cat_file, format(Sys.Date())), "")
n_sets <- 0L
for (i in which(is_hic)) {
  sid  <- sprintf("s%s", format(cc$id[i], scientific = FALSE, trim = TRUE))
  urls <- cc$paths[[i]]
  labs <- cc$labels[[i]]
  lines <- c(lines, sprintf("%s = root, %s", sid, names_col[i]))
  for (k in seq_along(urls)) {
    lab <- if (k <= length(labs) && nzchar(labs[k])) labs[k] else basename(urls[k])
    lines <- c(lines, sprintf("%s_%d = %s, %s, %s", sid, k, sid, lab, urls[k]))
    n_sets <- n_sets + 1L
  }
}
writeLines(lines, out_file)
cat(sprintf("Wrote %s: %d sample(s), %d dataset line(s)\n",
            out_file, sum(is_hic), n_sets))
