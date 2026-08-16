@echo off
setlocal
set "PKG=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PKG%scripts\validate_package.ps1"
set "RC=%ERRORLEVEL%"
exit /b %RC%
