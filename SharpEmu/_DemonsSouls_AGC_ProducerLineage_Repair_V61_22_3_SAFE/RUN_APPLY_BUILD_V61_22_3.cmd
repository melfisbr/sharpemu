@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_and_build.ps1"
exit /b %ERRORLEVEL%
