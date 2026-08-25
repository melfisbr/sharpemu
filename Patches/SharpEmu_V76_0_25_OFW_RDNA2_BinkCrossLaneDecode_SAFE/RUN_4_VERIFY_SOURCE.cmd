@echo off
setlocal
set "PKG=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PKG%scripts\verify_source.ps1"
exit /b %ERRORLEVEL%
