@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RUN_ALL_APPLY_BUILD_THEN_FINAL_TEST.ps1"
exit /b %ERRORLEVEL%
