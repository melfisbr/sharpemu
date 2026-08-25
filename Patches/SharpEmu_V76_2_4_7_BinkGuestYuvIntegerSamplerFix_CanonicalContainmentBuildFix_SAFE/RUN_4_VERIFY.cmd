@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\verify.ps1"
exit /b %ERRORLEVEL%
