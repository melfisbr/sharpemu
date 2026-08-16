@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_write_data_packet_position.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
