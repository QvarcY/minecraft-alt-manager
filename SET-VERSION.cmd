@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-tools\set-version.ps1" %*
if errorlevel 1 (
  echo.
  echo VERSION UPDATE FAILED.
  pause
  exit /b 1
)
echo.
pause
endlocal
