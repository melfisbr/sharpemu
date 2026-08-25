@echo off
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\precheck.ps1"
exit /b %ERRORLEVEL%
