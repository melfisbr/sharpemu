@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_diagnostic.ps1" -RepositoryRoot "%CD%\.."
exit /b %ERRORLEVEL%
