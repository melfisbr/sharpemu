@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_demons_diagnostic.ps1"
exit /b %ERRORLEVEL%
