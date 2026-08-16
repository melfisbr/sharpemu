@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate_package.ps1"
if errorlevel 1 exit /b %errorlevel%
