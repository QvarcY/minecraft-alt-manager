@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\uninstall-installed.ps1" -InstallDir "%LOCALAPPDATA%\QvarcY\MinecraftAltManager"
endlocal
