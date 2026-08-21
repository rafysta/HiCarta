@echo off
REM ==========================================================================
REM HiCarta - Windows launcher
REM Double-click to start the app. It opens in your default web browser.
REM Requires R (https://cran.r-project.org). First run installs packages.
REM ==========================================================================
setlocal
set "PORT=7788"
set "APPDIR=%~dp0"
set "PKGS=c('shiny','leaflet','htmlwidgets','base64enc','data.table','RColorBrewer','jsonlite','shinyFiles','readxl','writexl','DT','strawr','rtracklayer')"

REM --- guard: CMD cannot use a UNC path as the current directory ------------
REM     e.g. \\wsl.localhost\Ubuntu\home\you\HiCarta or \\server\share\HiCarta
REM     Without this check, CMD silently falls back to C:\Windows and every
REM     relative path below (R\install_libraries.R, runApp('.')) breaks.
if "%APPDIR:~0,2%"=="\\" goto :unc

cd /d "%APPDIR%"
if errorlevel 1 goto :nocd
if not exist "app.R" goto :noapp

REM --- locate Rscript -------------------------------------------------------
set "RSCRIPT="
where Rscript >nul 2>&1 && set "RSCRIPT=Rscript"
if not defined RSCRIPT (
  for /f "delims=" %%D in ('dir /b /ad /o-n "C:\Program Files\R\R-*" 2^>nul') do (
    if exist "C:\Program Files\R\%%D\bin\Rscript.exe" set "RSCRIPT=C:\Program Files\R\%%D\bin\Rscript.exe"
  )
)
if not defined RSCRIPT goto :noR
echo Using: %RSCRIPT%

REM --- free the port if a previous instance is still running ----------------
for /f "tokens=5" %%P in ('netstat -ano ^| findstr :%PORT% ^| findstr LISTENING') do (
  echo Closing previous instance PID %%P still using port %PORT% ...
  taskkill /F /PID %%P >nul 2>&1
)

REM --- first run: install packages if anything is missing -------------------
"%RSCRIPT%" -e "p<-%PKGS%; m<-p[!sapply(p,requireNamespace,quietly=TRUE)]; if(length(m)){cat('Missing packages:',paste(m,collapse=', '),'\n'); quit(status=10)}"
if not errorlevel 10 goto :launch

if not exist "R\install_libraries.R" goto :noinstaller
echo.
echo Installing required R packages (first run only).
echo The first run can take 10-20 minutes: rtracklayer is built from Bioconductor.
echo.
"%RSCRIPT%" "R\install_libraries.R"

REM --- verify the install really worked before starting the app -------------
"%RSCRIPT%" -e "p<-%PKGS%; m<-p[!sapply(p,requireNamespace,quietly=TRUE)]; if(length(m)){cat('STILL MISSING:',paste(m,collapse=', '),'\n'); quit(status=10)}"
if errorlevel 10 goto :pkgfail

REM --- launch ---------------------------------------------------------------
:launch
echo Starting HiCarta... a browser tab will open.
"%RSCRIPT%" -e "shiny::runApp('.', launch.browser=TRUE, port=%PORT%)"
if errorlevel 1 goto :runfail
pause
exit /b 0


REM ==========================================================================
REM Error paths
REM ==========================================================================
:unc
echo.
echo [ERROR] HiCarta is on a network / UNC path:
echo         %APPDIR%
echo.
echo Windows CMD cannot use a UNC path as the current directory, so this
echo launcher cannot find R\install_libraries.R or app.R from here.
echo.
echo If this path starts with \\wsl.localhost\ or \\wsl$\ , the files live
echo inside WSL. Either:
echo   1. Clone the repository onto the Windows filesystem and run it there:
echo        (in WSL)  cd /mnt/c/Users/%USERNAME%
echo                  git clone ^<repo-url^> HiCarta
echo      then double-click C:\Users\%USERNAME%\HiCarta\run_windows.bat
echo   2. Or install R inside WSL and start the app from the WSL shell:
echo        Rscript -e "shiny::runApp('.', port=%PORT%)"
echo      then open http://localhost:%PORT% in your Windows browser.
echo.
echo For a normal network share, map it to a drive letter first
echo (e.g. net use Z: \\server\share) and run the launcher from Z:.
echo.
pause
exit /b 1

:nocd
echo.
echo [ERROR] Could not change into the app directory:
echo         %APPDIR%
pause
exit /b 1

:noapp
echo.
echo [ERROR] app.R was not found in:
echo         %CD%
echo This launcher must stay in the HiCarta folder next to app.R and R\.
pause
exit /b 1

:noR
echo.
echo [ERROR] Could not find Rscript.
echo Install R from https://cran.r-project.org and try again.
echo (If R is installed somewhere other than C:\Program Files\R, add its
echo  bin folder to PATH.)
pause
exit /b 1

:noinstaller
echo.
echo [ERROR] Required R packages are missing, but R\install_libraries.R
echo         was not found in %CD%.
echo The download looks incomplete - re-clone the repository.
pause
exit /b 1

:pkgfail
echo.
echo [ERROR] Package installation did not complete - the packages listed
echo         above as STILL MISSING could not be installed.
echo.
echo Common causes:
echo   - No internet access, or a proxy / firewall blocking CRAN.
echo   - rtracklayer (Bioconductor) failed to build. Install Rtools matching
echo     your R version: https://cran.r-project.org/bin/windows/Rtools/
echo   - No write permission on the R library folder. Start R once and run
echo     install.packages("shiny") to let it create a personal library.
echo.
echo You can retry manually with:
echo   "%RSCRIPT%" "R\install_libraries.R"
pause
exit /b 1

:runfail
echo.
echo [ERROR] HiCarta exited with an error. See the messages above.
pause
exit /b 1
