@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\open_gui.ps1"
exit /b %ERRORLEVEL%
