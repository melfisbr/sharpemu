@echo off
setlocal
set "PKG=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PKG%scripts\apply_build.ps1"
exit /b %ERRORLEVEL%
