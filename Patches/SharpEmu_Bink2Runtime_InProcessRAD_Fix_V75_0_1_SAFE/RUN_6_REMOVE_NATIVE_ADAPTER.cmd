@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\remove_adapter.ps1"
exit /b %ERRORLEVEL%
