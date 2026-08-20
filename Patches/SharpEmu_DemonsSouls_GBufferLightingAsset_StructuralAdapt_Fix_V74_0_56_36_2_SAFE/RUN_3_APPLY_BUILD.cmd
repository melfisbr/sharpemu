@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate_package.ps1" -PackageRoot "%~dp0"
if errorlevel 1 exit /b %ERRORLEVEL%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\precheck.ps1" -RepositoryRoot "%CD%"
if errorlevel 1 exit /b %ERRORLEVEL%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_build.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
