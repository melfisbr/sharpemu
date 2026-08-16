@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\precheck.ps1" -RepositoryRoot "%CD%"
exit /b %errorlevel%
