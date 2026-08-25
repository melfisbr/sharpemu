@echo off
setlocal
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\patch_and_run.ps1"
exit /b %ERRORLEVEL%
