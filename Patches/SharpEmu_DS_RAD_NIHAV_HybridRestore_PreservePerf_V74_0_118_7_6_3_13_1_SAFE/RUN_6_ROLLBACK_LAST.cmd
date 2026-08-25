@echo off
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\rollback.ps1"
exit /b %ERRORLEVEL%
