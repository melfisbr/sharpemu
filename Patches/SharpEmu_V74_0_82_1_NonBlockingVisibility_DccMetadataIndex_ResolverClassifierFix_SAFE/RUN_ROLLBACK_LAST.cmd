@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rollback_last.ps1" -PackageRoot "%~dp0."
exit /b %ERRORLEVEL%
