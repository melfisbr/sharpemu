@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rollback_build_startup_test.ps1"
exit /b %ERRORLEVEL%
