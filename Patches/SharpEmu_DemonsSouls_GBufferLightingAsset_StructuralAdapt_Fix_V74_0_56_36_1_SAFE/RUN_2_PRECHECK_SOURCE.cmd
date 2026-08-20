@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\precheck.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
