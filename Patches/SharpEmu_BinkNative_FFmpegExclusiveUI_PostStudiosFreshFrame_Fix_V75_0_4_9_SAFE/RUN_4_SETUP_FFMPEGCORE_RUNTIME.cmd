@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup_ffmpegcore.ps1"
exit /b %ERRORLEVEL%
