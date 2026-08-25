@echo off
setlocal
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\precheck.ps1"
exit /b %ERRORLEVEL%
