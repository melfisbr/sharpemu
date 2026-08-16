@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_diagnostic.ps1" -RepositoryRoot "%CD%" -Eboot "F:\JOGOSPS5\PPSA01341\eboot.bin"
