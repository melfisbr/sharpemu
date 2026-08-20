# SharpEmu Demon's Souls Live-Log Native stderr Fix V74.0.88.4 SAFE

This package fixes only the V74.0.88.3 RUN_5 launcher.

V74.0.88.3 must already be installed. RUN_5 previously treated the first normal SharpEmu stderr log line as a terminating Windows PowerShell NativeCommandError.

V74.0.88.4 invokes SharpEmu through `cmd.exe`, with `2>&1` performed inside cmd, while continuing to flush every runtime line directly to `Patches`.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd
