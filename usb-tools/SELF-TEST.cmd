@echo off
setlocal
cd /d "%~dp0"
echo Minecraft ALT Manager package self-test
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\self-test.ps1" -UsbRoot "%~dp0"
echo.
pause
endlocal
