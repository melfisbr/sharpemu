# SharpEmu Demon's Souls In-Window IME + UI-Bink Uint Plane/Loop Fix V74.0.88.1 SAFE

This package moves the IME from an external host dialog into the SharpEmu presentation window and corrects a concrete typed-texture mismatch observed in the Demon's Souls UI-Bink path.

It also loops persistent UI movies such as `main_menu.bk2` at decoder EOF without telling the guest that the movie closed.

Execution order:
1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_PRECHECK.cmd`
3. `RUN_3_APPLY_BUILD.cmd`
4. `RUN_4_DIAGNOSTIC.cmd`
5. `RUN_5_TEST_DEMONS.cmd`

All generated build/runtime/result logs are written to the repository `Patches` directory.

## V74.0.88.1
Repairs the PowerShell `$Host` automatic-variable collision found by RUN_2 of V74.0.88. The source payload is unchanged.
