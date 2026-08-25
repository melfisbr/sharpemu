@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rollback_scripts.ps1"
exit /b %ERRORLEVEL%
