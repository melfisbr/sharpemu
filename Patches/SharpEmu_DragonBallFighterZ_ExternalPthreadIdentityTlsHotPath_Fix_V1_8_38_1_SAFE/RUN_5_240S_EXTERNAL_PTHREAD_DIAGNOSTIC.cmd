@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_logged.ps1" -Mode Diagnostic -Seconds 240
exit /b %ERRORLEVEL%
