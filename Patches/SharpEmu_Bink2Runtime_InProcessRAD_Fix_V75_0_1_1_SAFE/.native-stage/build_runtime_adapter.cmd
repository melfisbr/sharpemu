@echo off
call "H:\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b %errorlevel%
cl.exe /nologo /LD /O2 /EHsc /std:c++20 /utf-8 /Fo"C:\Users\Edpo\Documents\GitHub\sharpemu\Patches\SharpEmu_Bink2Runtime_InProcessRAD_Fix_V75_0_1_1_SAFE\.native-stage\SharpEmu.BinkNative.Runtime.obj" "C:\Users\Edpo\Documents\GitHub\sharpemu\Patches\SharpEmu_Bink2Runtime_InProcessRAD_Fix_V75_0_1_1_SAFE\source\native\SharpEmu.BinkNative.Runtime.cpp" /link /OUT:"C:\Users\Edpo\Documents\GitHub\sharpemu\Patches\SharpEmu_Bink2Runtime_InProcessRAD_Fix_V75_0_1_1_SAFE\.native-stage\SharpEmu.BinkNative.dll"
exit /b %errorlevel%
