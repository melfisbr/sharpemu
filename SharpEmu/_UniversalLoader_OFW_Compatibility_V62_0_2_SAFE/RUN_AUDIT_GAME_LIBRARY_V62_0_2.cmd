@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\audit_game_library.ps1" -RepositoryRoot "%CD%" -GamesRoot "F:\JOGOSPS5"
exit /b %ERRORLEVEL%
