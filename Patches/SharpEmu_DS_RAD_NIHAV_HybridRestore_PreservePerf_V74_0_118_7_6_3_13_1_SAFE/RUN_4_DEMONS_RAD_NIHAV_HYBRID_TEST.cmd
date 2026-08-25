@echo off
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\test_runtime.ps1"
exit /b %ERRORLEVEL%
