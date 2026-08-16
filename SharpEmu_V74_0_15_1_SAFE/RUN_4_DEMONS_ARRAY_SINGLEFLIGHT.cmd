@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_fastboot.ps1"
if errorlevel 1 exit /b %errorlevel%
