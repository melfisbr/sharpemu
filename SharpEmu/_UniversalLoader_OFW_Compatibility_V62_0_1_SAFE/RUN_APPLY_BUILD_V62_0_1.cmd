@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_build.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
