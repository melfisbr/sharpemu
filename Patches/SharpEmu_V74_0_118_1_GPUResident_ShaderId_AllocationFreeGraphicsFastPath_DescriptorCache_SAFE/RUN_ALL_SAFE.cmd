@echo off
setlocal
call "%~dp0RUN_1_VALIDATE_PACKAGE.cmd"
if errorlevel 1 exit /b %ERRORLEVEL%
call "%~dp0RUN_2_PRECHECK.cmd"
if errorlevel 1 exit /b %ERRORLEVEL%
call "%~dp0RUN_3_APPLY_BUILD.cmd"
if errorlevel 1 exit /b %ERRORLEVEL%
call "%~dp0RUN_4_TEST_DEMONS_SHADER.cmd"
if errorlevel 1 exit /b %ERRORLEVEL%
call "%~dp0RUN_5_ANALYZE_AND_PACKAGE_RESULT.cmd"
exit /b %ERRORLEVEL%
