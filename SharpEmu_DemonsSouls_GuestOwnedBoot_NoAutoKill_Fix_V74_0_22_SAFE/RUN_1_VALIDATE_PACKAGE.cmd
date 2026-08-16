@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate_package.ps1" %*
exit /b %ERRORLEVEL%
