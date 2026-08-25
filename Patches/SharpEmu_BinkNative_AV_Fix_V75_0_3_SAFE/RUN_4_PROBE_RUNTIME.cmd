@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\probe_runtime.ps1" %*
exit /b %ERRORLEVEL%
