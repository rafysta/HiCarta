@echo off
REM ==========================================================================
REM HiCarta - Windows launcher
REM Double-click to start the app. It opens in your default web browser.
REM Requires R (https://cran.r-project.org). First run installs packages.
REM ==========================================================================
setlocal
cd /d "%~dp0"
set "PORT=7788"

REM --- locate Rscript -------------------------------------------------------
set "RSCRIPT="
where Rscript >nul 2>&1 && set "RSCRIPT=Rscript"
if not defined RSCRIPT (
  for /f "delims=" %%D in ('dir /b /ad /o-n "C:\Program Files\R\R-*" 2^>nul') do (
    if exist "C:\Program Files\R\%%D\bin\Rscript.exe" set "RSCRIPT=C:\Program Files\R\%%D\bin\Rscript.exe"
  )
)
if not defined RSCRIPT (
  echo Could not find Rscript. Please install R from https://cran.r-project.org
  pause
  exit /b 1
)
echo Using: %RSCRIPT%

REM --- free the port if a previous instance is still running ----------------
for /f "tokens=5" %%P in ('netstat -ano ^| findstr :%PORT% ^| findstr LISTENING') do (
  echo Closing previous instance PID %%P still using port %PORT% ...
  taskkill /F /PID %%P >nul 2>&1
)

REM --- first run: install packages if anything is missing -------------------
"%RSCRIPT%" -e "pkgs<-c('shiny','leaflet','htmlwidgets','base64enc','data.table','RColorBrewer','strawr','rtracklayer'); if(!all(sapply(pkgs,requireNamespace,quietly=TRUE))) quit(status=10)"
if errorlevel 10 (
  echo Installing required R packages ^(first run only^)...
  "%RSCRIPT%" "R/install_libraries.R"
)

REM --- launch ---------------------------------------------------------------
echo Starting HiCarta... a browser tab will open.
"%RSCRIPT%" -e "shiny::runApp('.', launch.browser=TRUE, port=%PORT%)"
pause
