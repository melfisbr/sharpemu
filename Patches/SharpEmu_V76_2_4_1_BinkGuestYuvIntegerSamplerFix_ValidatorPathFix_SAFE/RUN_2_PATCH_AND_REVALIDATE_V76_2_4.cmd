@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\patch_target.ps1"
exit /b %ERRORLEVEL%
