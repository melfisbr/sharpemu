@echo off
setlocal
set "PKG=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PKG%scripts\run_large_array_cache.ps1"
set "RC=%ERRORLEVEL%"
exit /b %RC%
