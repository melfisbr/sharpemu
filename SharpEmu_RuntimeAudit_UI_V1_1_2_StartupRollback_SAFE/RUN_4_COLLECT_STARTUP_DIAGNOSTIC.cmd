@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_startup_diagnostic.ps1"
exit /b %ERRORLEVEL%
