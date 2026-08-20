@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rollback.ps1"
exit /b %errorlevel%
