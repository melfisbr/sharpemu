@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_build.ps1"
exit /b %ERRORLEVEL%
