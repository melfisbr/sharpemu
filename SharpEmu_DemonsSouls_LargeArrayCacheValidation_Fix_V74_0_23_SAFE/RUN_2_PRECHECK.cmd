@echo off
setlocal
set "PKG=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PKG%scripts\precheck.ps1"
set "RC=%ERRORLEVEL%"
exit /b %RC%
