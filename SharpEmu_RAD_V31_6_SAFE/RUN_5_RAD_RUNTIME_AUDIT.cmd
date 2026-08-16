@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rad_runtime_audit.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
