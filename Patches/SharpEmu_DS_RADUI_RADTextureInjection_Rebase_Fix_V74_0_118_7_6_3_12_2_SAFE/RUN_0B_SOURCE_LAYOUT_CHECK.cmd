@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\source_layout_check.ps1"
exit /b %ERRORLEVEL%
