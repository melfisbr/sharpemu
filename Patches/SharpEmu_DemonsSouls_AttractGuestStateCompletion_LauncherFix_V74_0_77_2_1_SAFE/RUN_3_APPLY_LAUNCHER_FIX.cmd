@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_fix.ps1"
exit /b %ERRORLEVEL%
