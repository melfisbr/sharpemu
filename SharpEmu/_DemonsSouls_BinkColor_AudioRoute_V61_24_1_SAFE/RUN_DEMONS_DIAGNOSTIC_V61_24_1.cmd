@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
