@echo off
setlocal
cd /d "%~dp0"
echo.
echo Building Minecraft ALT Manager USB package...
echo IT solutions by QvarcY - https://kas.id.lv
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD-USB.ps1"
if errorlevel 1 (
  echo.
  echo BUILD FAILED.
  pause
  exit /b 1
)
echo.
pause
endlocal
