@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_build.ps1" -RepositoryRoot "%CD%" -Eboot "F:\JOGOSPS5\PPSA01341\eboot.bin"
exit /b %ERRORLEVEL%
