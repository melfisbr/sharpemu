@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_guest_owned_boot.ps1" %*
exit /b %ERRORLEVEL%
