@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\analyze_result.ps1"
exit /b %ERRORLEVEL%
