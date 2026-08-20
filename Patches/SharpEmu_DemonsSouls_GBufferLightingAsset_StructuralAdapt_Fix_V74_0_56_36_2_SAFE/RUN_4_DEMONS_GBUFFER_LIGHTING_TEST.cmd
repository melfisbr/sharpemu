@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate_package.ps1" -PackageRoot "%~dp0"
if errorlevel 1 exit /b %ERRORLEVEL%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_test.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
