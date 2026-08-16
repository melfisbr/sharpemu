@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_stale_source_refresh.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
