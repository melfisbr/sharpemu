@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_large_array_baseline.ps1" -RepositoryRoot "%CD%"
exit /b %errorlevel%
