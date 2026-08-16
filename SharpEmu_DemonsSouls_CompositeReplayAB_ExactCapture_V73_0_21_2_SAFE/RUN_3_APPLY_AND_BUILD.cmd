@echo off
setlocal
echo [V73.0.21.2] NOTE: no patch is applied; this step builds the exact current source.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" -RepoRoot "%CD%" -Eboot "F:\JOGOSPS5\PPSA01341\eboot.bin"
exit /b %ERRORLEVEL%
