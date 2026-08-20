@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\post_audit.ps1"
exit /b %ERRORLEVEL%
