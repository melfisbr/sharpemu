@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate.ps1" -PackageRoot "%~dp0."
exit /b %ERRORLEVEL%
