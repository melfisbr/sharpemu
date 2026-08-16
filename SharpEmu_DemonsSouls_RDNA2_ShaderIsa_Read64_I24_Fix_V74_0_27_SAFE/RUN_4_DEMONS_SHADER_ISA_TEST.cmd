@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_shader_isa.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
