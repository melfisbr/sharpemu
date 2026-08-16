@echo off
setlocal
rem V31.7.5: %~dp0 ends in a backslash; append dot so Windows argument parsing
rem cannot treat the final backslash as escaping the closing quote.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate_package.ps1" -PackageRoot "%~dp0."
exit /b %ERRORLEVEL%
