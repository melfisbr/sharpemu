@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\precheck.ps1"
exit /b %ERRORLEVEL%
