@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\diagnostic.ps1" -Seconds 240
exit /b %ERRORLEVEL%
