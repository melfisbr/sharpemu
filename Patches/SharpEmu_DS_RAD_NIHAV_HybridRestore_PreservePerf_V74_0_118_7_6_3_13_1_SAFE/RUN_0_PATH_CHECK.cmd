@echo off
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\path_check.ps1"
exit /b %ERRORLEVEL%
