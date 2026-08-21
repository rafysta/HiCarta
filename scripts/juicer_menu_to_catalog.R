#!/usr/bin/env Rscript
# ============================================================================
# juicer_menu_to_catalog.R - convert a legacy Juicer-style menu file into an
# Excel data catalog (.xlsx) HiCarta can load.
#
# Usage:
#   Rscript scripts/juicer_menu_to_catalog.R MENU.txt CATALOG.xlsx [--collapse]
#
#   MENU.txt      the old menu (lines "<id> = <parent>, <label>[, <url>]")
#   CATALOG.xlsx  output catalog; one row per sample, the sample's datasets
#                 ";"-joined into the path / label columns
#   --collapse    additionally strip legacy per-normalization suffixes
#                 (e.g. NAME_ICE.5kb.hic, NAME_KR.hic -> NAME.hic) and drop
#                 duplicates - useful after regenerating data as single
#                 multi-resolution .hic files that carry their normalizations.
#
# Run from the HiCarta folder (the script sources R/juicer_menu.R).
# Requires: writexl  (install.packages("writexl"))
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
collapse <- "--collapse" %in% args
args <- setdiff(args, "--collapse")
if (length(args) != 2) {
  cat("Usage: Rscript scripts/juicer_menu_to_catalog.R MENU.txt CATALOG.xlsx [--collapse]\n")
  quit(status = 1)
}
menu_file <- args[1]; out_file <- args[2]
if (!file.exists(menu_file)) stop("menu file not found: ", menu_file)
if (!requireNamespace("writexl", quietly = TRUE))
  stop('package "writexl" is required:  install.packages("writexl")')

# locate R/juicer_menu.R relative to this script so it also works when the
# script is started from another directory
script_dir <- tryCatch({
  f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  dirname(normalizePath(sub("^--file=", "", f[1])))
}, error = function(e) "scripts")
app_dir <- dirname(script_dir)
source(file.path(app_dir, "R", "juicer_menu.R"))

menu <- parse_juicer_menu(menu_file)
if (nrow(menu) == 0) stop("no datasets found in ", menu_file)

# strip a trailing normalization/resolution tag from a legacy file name:
#   wt_ICE.5kb.hic / wt_KR.hic / wt_Raw.100kb.hic -> wt.hic
collapse_url <- function(u)
  sub("_(ICE|KR|SCALE|VC|VC_SQRT|RAW|NONE)([._-][0-9]+[KM]?B)?\\.hic$",
      ".hic", u, ignore.case = TRUE)

rows <- lapply(split(menu, menu$sample_id)[unique(menu$sample_id)], function(g) {
  urls <- g$url; labs <- g$dataset_label
  if (collapse) {
    urls <- collapse_url(urls)
    keep <- !duplicated(urls)
    urls <- urls[keep]
    labs <- if (sum(keep) == 1) "" else labs[keep]
  }
  data.frame(name  = g$sample_label[1],
             path  = paste(urls, collapse = ";"),
             label = paste(labs, collapse = ";"),
             stringsAsFactors = FALSE)
})
cat_df <- do.call(rbind, rows)
cat_df <- data.frame(id        = seq_len(nrow(cat_df)),
                     name      = cat_df$name,
                     file_type = "hic",
                     path      = cat_df$path,
                     label     = cat_df$label,
                     comment   = "",
                     stringsAsFactors = FALSE)
writexl::write_xlsx(list(catalog = cat_df), out_file)
cat(sprintf("Wrote %s: %d sample(s), %d dataset(s)%s\n",
            out_file, nrow(cat_df), nrow(menu),
            if (collapse) " (legacy names collapsed)" else ""))
