@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate.ps1"
exit /b %ERRORLEVEL%
