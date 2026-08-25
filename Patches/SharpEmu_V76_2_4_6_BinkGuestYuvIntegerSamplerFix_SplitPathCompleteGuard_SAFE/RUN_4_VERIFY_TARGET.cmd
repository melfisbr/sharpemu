@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\verify_target.ps1"
exit /b %ERRORLEVEL%
