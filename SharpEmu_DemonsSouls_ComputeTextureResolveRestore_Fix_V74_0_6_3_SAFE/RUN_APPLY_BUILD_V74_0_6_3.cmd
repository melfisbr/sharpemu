@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_build.ps1" -RepositoryRoot "%CD%\.."
exit /b %ERRORLEVEL%
