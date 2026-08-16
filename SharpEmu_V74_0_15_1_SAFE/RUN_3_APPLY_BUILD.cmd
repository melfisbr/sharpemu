@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_build.ps1"
if errorlevel 1 exit /b %errorlevel%
