@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rollback.ps1"
exit /b %ERRORLEVEL%
