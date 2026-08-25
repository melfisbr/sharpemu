@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\restore_build.ps1"
exit /b %ERRORLEVEL%
