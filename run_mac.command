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
  echo "Could not find Rscript. Please install R from https://cran.r-project.org"
  read -r -p "Press Enter to close..." _
  exit 1
fi
echo "Using: $RSCRIPT"

# --- free the port if a previous instance is still running ----------------
PIDS="$(lsof -ti tcp:$PORT -sTCP:LISTEN 2>/dev/null)"
if [ -n "$PIDS" ]; then
  echo "Closing previous instance (PID $PIDS) still using port $PORT ..."
  kill -9 $PIDS 2>/dev/null
fi

# --- first run: install packages if anything is missing -------------------
"$RSCRIPT" -e "pkgs<-c('shiny','leaflet','htmlwidgets','base64enc','data.table','RColorBrewer','strawr','rtracklayer'); if(!all(sapply(pkgs,requireNamespace,quietly=TRUE))) quit(status=10)"
if [ $? -eq 10 ]; then
  echo "Installing required R packages (first run only)..."
  "$RSCRIPT" "R/install_libraries.R"
fi

# --- launch ---------------------------------------------------------------
echo "Starting HiCarta... a browser tab will open."
"$RSCRIPT" -e "shiny::runApp('.', launch.browser=TRUE, port=$PORT)"
read -r -p "Press Enter to close..." _
