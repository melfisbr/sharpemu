@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\normal_launch.ps1"
exit /b %ERRORLEVEL%
