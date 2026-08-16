@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate_package.ps1"
exit /b %errorlevel%
