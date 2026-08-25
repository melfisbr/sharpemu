@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\undo_restore.ps1"
exit /b %ERRORLEVEL%
