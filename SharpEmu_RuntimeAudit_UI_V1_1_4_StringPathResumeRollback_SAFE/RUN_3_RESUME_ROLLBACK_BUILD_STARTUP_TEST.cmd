@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\resume_rollback_build_startup_test.ps1"
exit /b %ERRORLEVEL%
