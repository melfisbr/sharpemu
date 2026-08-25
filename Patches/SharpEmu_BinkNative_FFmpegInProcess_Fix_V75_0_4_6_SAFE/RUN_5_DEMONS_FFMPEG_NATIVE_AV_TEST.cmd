@echo off
setlocal
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test.ps1" -EbootPath "%~1"
)
exit /b %ERRORLEVEL%
