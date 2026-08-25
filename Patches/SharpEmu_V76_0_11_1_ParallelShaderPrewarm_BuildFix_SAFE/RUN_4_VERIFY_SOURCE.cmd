@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\verify_source.ps1"
exit /b %ERRORLEVEL%
