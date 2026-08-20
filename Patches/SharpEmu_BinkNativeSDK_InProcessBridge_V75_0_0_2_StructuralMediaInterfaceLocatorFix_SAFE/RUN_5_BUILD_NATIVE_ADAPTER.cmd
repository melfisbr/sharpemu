@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_native_adapter.ps1"
exit /b %ERRORLEVEL%
