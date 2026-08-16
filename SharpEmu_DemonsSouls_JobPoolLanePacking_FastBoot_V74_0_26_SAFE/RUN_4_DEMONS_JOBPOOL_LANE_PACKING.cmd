@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_jobpool_lane_packing.ps1" -RepositoryRoot "%CD%"
exit /b %ERRORLEVEL%
