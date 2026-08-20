@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_test.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
