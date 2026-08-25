@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\search_runtime_tree.ps1" %*
exit /b %ERRORLEVEL%
