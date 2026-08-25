@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_adapter.ps1" %*
exit /b %ERRORLEVEL%
