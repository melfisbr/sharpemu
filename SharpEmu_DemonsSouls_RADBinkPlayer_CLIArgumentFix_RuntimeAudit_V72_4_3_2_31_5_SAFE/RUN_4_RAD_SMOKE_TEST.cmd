@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rad_smoke_test.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
