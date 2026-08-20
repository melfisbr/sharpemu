@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_test_diagnostic.ps1" -PackageRoot "%~dp0."
exit /b %ERRORLEVEL%
