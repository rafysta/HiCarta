#!/usr/bin/env Rscript
# Install the R packages HiD contact viewer v4 needs.
# Run once:  Rscript R/install_libraries.R

repos <- "https://cloud.r-project.org"
need <- c("shiny", "data.table", "RColorBrewer",
          "leaflet", "htmlwidgets", "base64enc",   # leaflet* = tiled viewer
          "jsonlite",                              # session save/restore (.json)
          "curl",                                  # HTTP range reads for remote .hic
          "shinyFiles",                            # local file picker dialogs
          "readxl",                                # Excel data catalog (.xlsx)
          "writexl",                               # bookmark / catalog .xlsx export
          "DT")                                    # catalog sample table
for (p in need) {
  if (!requireNamespace(p, quietly = TRUE)) {
    message("Installing ", p, " …")
    install.packages(p, repos = repos)
  }
}

# strawr is OPTIONAL. .hic files are read by R/hic_reader.R, a pure-R stateful
# reader that needs no compiler and streams remote files over HTTP range
# requests. strawr is only used as a fallback for a .hic the native reader
# cannot parse, and by the "strawr"/"download" engines
# (options(hicarta.hic_engine=)). Install it if you want that safety net.
if (!requireNamespace("strawr", quietly = TRUE)) {
  message("Installing strawr (optional fallback .hic reader) …")
  tryCatch(install.packages("strawr", repos = repos),
           error = function(e) NULL)
  if (!requireNamespace("strawr", quietly = TRUE))
    message("  strawr not installed - fine, the native reader does not need it.")
}

# rtracklayer (Bioconductor): reads bigWig / BED tracks. First install is slow.
if (!requireNamespace("rtracklayer", quietly = TRUE)) {
  message("Installing rtracklayer (Bioconductor; this can take several minutes) …")
  if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager", repos = repos)
  BiocManager::install("rtracklayer", update = FALSE, ask = FALSE)
}

message("Done. Installed: ",
        paste(c(need, "strawr")[
          vapply(c(need, "strawr"), requireNamespace, logical(1), quietly = TRUE)],
          collapse = ", "))
