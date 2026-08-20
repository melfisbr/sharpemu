# SharpEmu Demon's Souls V74.0.86.1.4 SAFE

This package fixes the C# compilation failure in V74.0.86.1.3 while preserving its successful structural Presenter patch strategy.

The OSK PowerShell script is now encoded as UTF-16LE Base64 and passed directly to `powershell.exe -EncodedCommand`. This removes C# quote escaping from the OSK implementation entirely.

Run in order:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd
