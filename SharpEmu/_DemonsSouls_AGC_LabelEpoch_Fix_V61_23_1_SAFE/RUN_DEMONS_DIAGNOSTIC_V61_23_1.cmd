@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_demons_diagnostic.ps1" -RepositoryRoot "%~dp0..\.."
exit /b %errorlevel%
