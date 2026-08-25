@echo off
setlocal
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate.ps1"
exit /b %ERRORLEVEL%
