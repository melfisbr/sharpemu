@echo off
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\apply_build.ps1"
exit /b %ERRORLEVEL%
