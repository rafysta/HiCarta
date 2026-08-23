#!/usr/bin/env Rscript
# Install the R packages HiCarta needs.
# Run once:  Rscript R/install_libraries.R
#
# The package list itself lives in R/required_packages.R, shared with the two
# launchers. Set HICARTA_SKIP_BIOC=1 to skip the slow rtracklayer install.

repos <- "https://cloud.r-project.org"

# --- find required_packages.R next to this script -------------------------
local({
  a    <- commandArgs(trailingOnly = FALSE)
  f    <- sub("^--file=", "", a[grep("^--file=", a)])
  cand <- c(if (length(f)) file.path(dirname(f[1]), "required_packages.R"),
            file.path("R", "required_packages.R"),
            "required_packages.R")
  hit  <- cand[file.exists(cand)]
  if (!length(hit))
    stop("required_packages.R not found next to install_libraries.R - the ",
         "download looks incomplete; re-clone the repository.")
  source(hit[1])          # local = FALSE, so it lands in the global env
})

# --------------------------------------------------------------------------
# Never build from source on a user machine.
#
# On macOS and Windows, CRAN ships pre-built binaries. When the CRAN *source*
# version of a package is newer than the binary available for the installed R
# - normal on an older R, e.g. 4.2, whose binary repository is frozen - a
# NON-INTERACTIVE Rscript session does not ask "install from sources?", it
# just builds from source. That needs a working C/C++ toolchain (Xcode
# Command Line Tools on macOS, Rtools on Windows). Where that toolchain is
# missing or incomplete, every package with compiled code fails - including
# shiny - and the app cannot start.
#
# A slightly older binary is fine for HiCarta, so ask for binaries explicitly
# and fall back to source only when no binary exists at all.
# --------------------------------------------------------------------------
options(install.packages.compile.from.source = "never")

sysname  <- Sys.info()[["sysname"]]
has_bin  <- sysname %in% c("Darwin", "Windows")  # CRAN Linux is source-only
pkg_type <- if (has_bin) "binary" else getOption("pkgType")

if (has_bin && getRversion() < "4.3.0")
  message("Note: this is R ", getRversion(), ", which is several years old. ",
          "Installing\n  pre-built packages instead of building them. If ",
          "anything below still fails,\n  installing the current R from ",
          "https://cran.r-project.org is the cleanest fix.\n")

install_one <- function(p) {
  if (requireNamespace(p, quietly = TRUE)) return(TRUE)
  message("Installing ", p, " ...")
  try(install.packages(p, repos = repos, type = pkg_type), silent = TRUE)
  if (requireNamespace(p, quietly = TRUE)) return(TRUE)
  if (has_bin) {
    message("  no pre-built ", p, " for R ", getRversion(),
            " - trying to build it (needs a compiler) ...")
    try(install.packages(p, repos = repos, type = "source"), silent = TRUE)
  }
  requireNamespace(p, quietly = TRUE)
}

invisible(lapply(HICARTA_REQUIRED, install_one))

# --- optional: strawr (fallback .hic reader) ------------------------------
if (!requireNamespace("strawr", quietly = TRUE)) {
  message("strawr is optional - a fallback .hic reader.")
  if (!install_one("strawr"))
    message("  strawr not installed - fine, the native .hic reader does not ",
            "need it.")
}

# --- optional: rtracklayer (Bioconductor; BED / GFF3 tracks) --------------
# The first install can take 10-20 minutes. HICARTA_SKIP_BIOC=1 skips it.
if (!requireNamespace("rtracklayer", quietly = TRUE) &&
    !nzchar(Sys.getenv("HICARTA_SKIP_BIOC"))) {
  message("rtracklayer is optional - BED / GFF3 tracks. It comes from ",
          "Bioconductor\n  and can take several minutes.")
  install_one("BiocManager")
  if (requireNamespace("BiocManager", quietly = TRUE))
    try(BiocManager::install("rtracklayer", update = FALSE, ask = FALSE),
        silent = TRUE)
  if (!requireNamespace("rtracklayer", quietly = TRUE))
    message("  rtracklayer not installed - contact maps and bigWig tracks ",
            "still work;\n  BED / GFF3 tracks will not.")
}

# --- report ---------------------------------------------------------------
have <- function(p) requireNamespace(p, quietly = TRUE)
opt  <- HICARTA_OPTIONAL[vapply(HICARTA_OPTIONAL, have, logical(1))]
miss <- hicarta_missing()

message("")
if (!length(miss)) {
  message("Done. All required packages are installed.")
  if (length(opt)) message("Optional, also installed: ", paste(opt, collapse = ", "))
} else {
  message("Some required packages could NOT be installed: ",
          paste(miss, collapse = ", "))
  message("")
  message("Common causes:")
  message("  - No internet access, or a proxy / firewall blocking CRAN.")
  if (sysname == "Darwin") {
    message("  - Xcode Command Line Tools missing or incomplete. Install with:")
    message("        xcode-select --install")
  } else if (sysname == "Windows") {
    message("  - Rtools missing (only needed if a package has to be built):")
    message("        https://cran.r-project.org/bin/windows/Rtools/")
  }
  if (getRversion() < "4.3.0")
    message("  - This R (", getRversion(), ") is old enough that CRAN no ",
            "longer publishes new\n    binaries for it. Installing the ",
            "current R from https://cran.r-project.org\n    usually fixes ",
            "this outright.")
  message("  - No write permission on the R library folder. Start R once and run")
  message("        install.packages(\"shiny\")")
  message("    to let it create a personal library.")
  quit(status = 1)
}
