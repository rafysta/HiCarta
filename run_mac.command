#!/bin/bash
# ==========================================================================
# HiCarta - macOS launcher
# Double-click to start the app. It opens in your default web browser.
# Requires R (https://cran.r-project.org). First run installs packages.
# If double-click is blocked by Gatekeeper: right-click > Open, or run
#   chmod +x run_mac.command   in Terminal once.
# ==========================================================================
cd "$(dirname "$0")" || exit 1
PORT=7788

fail() {
  echo
  echo "$@"
  echo
  read -r -p "Press Enter to close..." _
  exit 1
}

if [ ! -f app.R ]; then
  fail "[ERROR] app.R was not found in:
        $(pwd)
This launcher must stay in the HiCarta folder, next to app.R and R/."
fi
if [ ! -f R/required_packages.R ] || [ ! -f R/install_libraries.R ]; then
  fail "[ERROR] R/required_packages.R or R/install_libraries.R was not found in:
        $(pwd)
The download looks incomplete - re-clone the repository."
fi

# --- locate Rscript -------------------------------------------------------
RSCRIPT=""
if command -v Rscript >/dev/null 2>&1; then
  RSCRIPT="$(command -v Rscript)"
else
  for p in /opt/homebrew/bin/Rscript /usr/local/bin/Rscript \
           /Library/Frameworks/R.framework/Resources/bin/Rscript; do
    if [ -x "$p" ]; then RSCRIPT="$p"; break; fi
  done
fi
if [ -z "$RSCRIPT" ]; then
  fail "[ERROR] Could not find Rscript.
Install R from https://cran.r-project.org and try again."
fi
echo "Using: $RSCRIPT"

# --- free the port if a previous instance is still running ----------------
PIDS="$(lsof -ti tcp:$PORT -sTCP:LISTEN 2>/dev/null)"
if [ -n "$PIDS" ]; then
  echo "Closing previous instance (PID $PIDS) still using port $PORT ..."
  # shellcheck disable=SC2086
  kill -9 $PIDS 2>/dev/null
fi

# --- first run: install packages if anything is missing -------------------
# The required list lives in R/required_packages.R. Do NOT keep a second copy
# here: the launcher used to list strawr and rtracklayer, which the installer
# treats as optional, so on a machine that cannot build them the check failed
# on every start and re-ran the whole installer.
check_pkgs() {
  "$RSCRIPT" -e "source('R/required_packages.R'); m <- hicarta_missing(); if (length(m)) { cat('Missing packages:', paste(m, collapse=', '), '\n'); quit(status=10) }"
}

if ! check_pkgs; then
  echo
  echo "Installing required R packages (first run only)."
  echo "This can take 10-20 minutes: rtracklayer is built from Bioconductor."
  echo
  "$RSCRIPT" R/install_libraries.R

  # --- verify the install really worked before starting the app -----------
  if ! check_pkgs; then
    fail "[ERROR] Package installation did not complete - the packages listed
        above as missing could not be installed.

Common causes:
  - No internet access, or a proxy / firewall blocking CRAN.
  - An old R. CRAN stops publishing new pre-built packages for old R
    releases, so they have to be built from source instead. Installing the
    current R from https://cran.r-project.org is usually the quickest fix.
  - Xcode Command Line Tools missing or incomplete, which is what breaks
    that build. Install them with:
        xcode-select --install
  - No write permission on the R library folder. Start R once and run
        install.packages(\"shiny\")
    to let it create a personal library.

You can retry manually with:
    \"$RSCRIPT\" R/install_libraries.R"
  fi
fi

# --- launch ---------------------------------------------------------------
echo "Starting HiCarta... a browser tab will open."
if ! "$RSCRIPT" -e "shiny::runApp('.', launch.browser=TRUE, port=$PORT)"; then
  fail "[ERROR] HiCarta exited with an error. See the messages above."
fi
read -r -p "Press Enter to close..." _
