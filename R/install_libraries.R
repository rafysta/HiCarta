#!/usr/bin/env Rscript
# Install the R packages HiD contact viewer v4 needs.
# Run once:  Rscript R/install_libraries.R

repos <- "https://cloud.r-project.org"
need <- c("shiny", "data.table", "RColorBrewer",
          "leaflet", "htmlwidgets", "base64enc",   # leaflet* = tiled viewer
          "jsonlite",                              # session save/restore (.json)
          "shinyFiles")                            # local .hic file picker dialog
for (p in need) {
  if (!requireNamespace(p, quietly = TRUE)) {
    message("Installing ", p, " …")
    install.packages(p, repos = repos)
  }
}

# strawr (reads .hic). On CRAN as of recent versions; fall back to GitHub.
if (!requireNamespace("strawr", quietly = TRUE)) {
  ok <- tryCatch({ install.packages("strawr", repos = repos); TRUE },
                 error = function(e) FALSE)
  if (!requireNamespace("strawr", quietly = TRUE)) {
    if (!requireNamespace("remotes", quietly = TRUE))
      install.packages("remotes", repos = repos)
    remotes::install_github("aidenlab/straw/R")
  }
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
