@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\capture.ps1" -RepoRoot "%CD%" -Eboot "F:\JOGOSPS5\PPSA01341\eboot.bin"
exit /b %ERRORLEVEL%
