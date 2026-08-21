#!/usr/bin/env Rscript
# ============================================================================
# catalog_to_igv_xml.R - export the track rows of an Excel data catalog back
# to a legacy IGV track-list XML file.
#
# Usage:
#   Rscript scripts/catalog_to_igv_xml.R CATALOG.xlsx TRACKS.xml
#
# Every valid catalog row whose file_type is "bigwig" or "bed" becomes one
# <Resource> per ";"-separated path entry, grouped into <Category> blocks by
# the "project" column (rows without a project go into "Tracks").
#
# Run from the HiCarta folder (the script sources R/i18n.R and R/catalog.R).
# Requires: readxl  (already required by HiCarta itself)
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  cat("Usage: Rscript scripts/catalog_to_igv_xml.R CATALOG.xlsx TRACKS.xml\n")
  quit(status = 1)
}
cat_file <- args[1]; out_file <- args[2]

script_dir <- tryCatch({
  f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  dirname(normalizePath(sub("^--file=", "", f[1])))
}, error = function(e) "scripts")
app_dir <- dirname(script_dir)
source(file.path(app_dir, "R", "i18n.R"))
source(file.path(app_dir, "R", "catalog.R"))

xml_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  x <- gsub(">", "&gt;",  x, fixed = TRUE)
  gsub('"', "&quot;", x, fixed = TRUE)
}

cc <- read_catalog(cat_file)
if (!isTRUE(cc$ok)) stop("could not read catalog: ", cc$fatal)
if (nrow(cc$errors) > 0)
  cat(sprintf("Note: %d broken row(s) were excluded (open the catalog in HiCarta to see why).\n",
              nrow(cc$errors)))

is_trk <- !is.na(cc$file_type) & cc$file_type %in% c("bigwig", "bed")
if (!any(is_trk)) stop("the catalog has no valid track (bigwig / bed) rows")

canon <- tolower(trimws(names(cc$data)))
col_of <- function(key, default = "") {
  j <- which(canon == key)[1]
  if (is.na(j)) rep(default, nrow(cc$data)) else {
    x <- cc$data[[j]]; ifelse(is.na(x) | !nzchar(trimws(x)), default, trimws(x))
  }
}
names_col <- col_of("name")
proj_col  <- col_of("project", "Tracks")

res <- list()   # category -> character vector of <Resource> lines
n_res <- 0L
for (i in which(is_trk)) {
  urls <- cc$paths[[i]]; labs <- cc$labels[[i]]
  for (k in seq_along(urls)) {
    # single entry -> the sample name; several entries -> "name / entry label"
    # (read_catalog falls back to the file's basename when label is empty)
    nm <- if (length(urls) == 1) names_col[i]
          else sprintf("%s / %s", names_col[i],
                       if (k <= length(labs) && nzchar(labs[k])) labs[k]
                       else basename(urls[k]))
    line <- sprintf('    <Resource name="%s" path="%s"/>',
                    xml_escape(nm), xml_escape(urls[k]))
    res[[proj_col[i]]] <- c(res[[proj_col[i]]], line)
    n_res <- n_res + 1L
  }
}

lines <- c('<?xml version="1.0" encoding="UTF-8"?>',
           sprintf('<Global name="%s" version="1">',
                   xml_escape(basename(cat_file))))
for (cat_name in names(res))
  lines <- c(lines,
             sprintf('  <Category name="%s">', xml_escape(cat_name)),
             res[[cat_name]],
             "  </Category>")
lines <- c(lines, "</Global>")
writeLines(lines, out_file)
cat(sprintf("Wrote %s: %d track(s) in %d categorie(s)\n",
            out_file, n_res, length(res)))
