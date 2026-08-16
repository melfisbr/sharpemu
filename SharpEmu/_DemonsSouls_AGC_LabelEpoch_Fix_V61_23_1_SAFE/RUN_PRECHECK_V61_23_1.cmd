@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\precheck.ps1" -RepositoryRoot "%~dp0..\.."
exit /b %errorlevel%
