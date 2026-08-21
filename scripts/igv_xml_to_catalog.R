#!/usr/bin/env Rscript
# ============================================================================
# igv_xml_to_catalog.R - convert a legacy IGV track-list XML into an Excel
# data catalog (.xlsx) HiCarta can load.
#
# Usage:
#   Rscript scripts/igv_xml_to_catalog.R TRACKS.xml CATALOG.xlsx
#
# One catalog row per <Resource>; the XML <Category> name is stored in the
# "project" column so it comes back as a filter in the catalog list.
#
# Run from the HiCarta folder (the script sources R/tracks.R).
# Requires: writexl  (install.packages("writexl"))
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  cat("Usage: Rscript scripts/igv_xml_to_catalog.R TRACKS.xml CATALOG.xlsx\n")
  quit(status = 1)
}
xml_file <- args[1]; out_file <- args[2]
if (!grepl("^https?://", xml_file) && !file.exists(xml_file))
  stop("XML file not found: ", xml_file)
if (!requireNamespace("writexl", quietly = TRUE))
  stop('package "writexl" is required:  install.packages("writexl")')

script_dir <- tryCatch({
  f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  dirname(normalizePath(sub("^--file=", "", f[1])))
}, error = function(e) "scripts")
app_dir <- dirname(script_dir)
source(file.path(app_dir, "R", "tracks.R"))   # parse_igv_xml()

tl <- parse_igv_xml(xml_file)
if (nrow(tl) == 0) stop("no <Resource> entries found in ", xml_file)

# undo XML attribute escaping (parse_igv_xml returns raw attribute text)
xml_unescape <- function(x) {
  x <- gsub("&lt;",   "<", x, fixed = TRUE)
  x <- gsub("&gt;",   ">", x, fixed = TRUE)
  x <- gsub("&quot;", '"', x, fixed = TRUE)
  x <- gsub("&apos;", "'", x, fixed = TRUE)
  gsub("&amp;", "&", x, fixed = TRUE)
}
tl$name <- xml_unescape(tl$name)
tl$path <- xml_unescape(tl$path)
tl$category <- xml_unescape(tl$category)

cat_df <- data.frame(
  id        = seq_len(nrow(tl)),
  name      = tl$name,
  file_type = ifelse(tolower(tl$type) == "bed", "bed", "bigwig"),
  project   = tl$category,
  path      = tl$path,
  comment   = "",
  stringsAsFactors = FALSE)
writexl::write_xlsx(list(catalog = cat_df), out_file)
cat(sprintf("Wrote %s: %d track(s) in %d categorie(s)\n",
            out_file, nrow(cat_df), length(unique(tl$category))))
