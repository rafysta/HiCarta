# ==========================================================================
# HiCarta - the package list, in one place.
#
# Sourced by R/install_libraries.R and by both launchers (run_mac.command,
# run_windows.bat) so the three can never disagree about what is required.
#
# They did disagree once, and it hurt: the launchers listed 'strawr' and
# 'rtracklayer' as required while the installer treated them as optional.
# Neither of those installs without a C/C++ toolchain, so on a machine
# without one the launcher saw "packages missing" on EVERY start and re-ran
# the full installer, which failed again - minutes of red text before each
# launch. Keep this file the single source of truth.
# ==========================================================================

# --- required: the app cannot start without these -------------------------
HICARTA_REQUIRED <- c(
  "shiny",                                # the app itself
  "leaflet", "htmlwidgets", "base64enc",  # tiled contact-map viewer
  "data.table", "RColorBrewer",           # binning, palettes
  "jsonlite",                             # session save / restore (.json)
  "curl",                                 # HTTP range reads for remote files
  "shinyFiles",                           # local file picker dialogs
  "readxl",                               # Excel data catalog (.xlsx)
  "writexl",                              # bookmark / catalog .xlsx export
  "DT"                                    # catalog sample table
)

# --- optional: never block startup on these -------------------------------
# strawr       fallback .hic reader. .hic is normally read by R/hic_reader.R,
#              a pure-R reader that needs no compiler and streams remote files
#              over HTTP range requests. strawr is only used for a .hic the
#              native reader cannot parse, and by the "strawr" / "download"
#              engines (options(hicarta.hic_engine=)).
#
# rtracklayer  fallback bigWig reader, and the only reader for BED / GFF3
#              (Bioconductor). bigWig is normally read by R/bigwig_reader.R,
#              which is also pure R and, unlike rtracklayer, can stream a
#              bigWig over http(s).
#              Note: rtracklayer also brings GenomicRanges / IRanges, which
#              R/tracks.R uses to represent every track. Without it the
#              contact map works fine, but adding a track will fail.
HICARTA_OPTIONAL <- c("strawr", "rtracklayer")

# --- which required packages are not installed (character(0) = all fine) ---
hicarta_missing <- function(pkgs = HICARTA_REQUIRED) {
  pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
}
