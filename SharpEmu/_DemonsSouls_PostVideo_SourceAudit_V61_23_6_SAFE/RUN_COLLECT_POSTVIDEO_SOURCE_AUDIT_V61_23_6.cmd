@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_source_audit.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
