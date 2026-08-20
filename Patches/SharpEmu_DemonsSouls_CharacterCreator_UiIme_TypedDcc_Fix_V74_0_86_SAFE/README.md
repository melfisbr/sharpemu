# SharpEmu Demon's Souls Character Creator UI + IME V74.0.86 SAFE

Run from `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches` in this order:

1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_PRECHECK.cmd`
3. `RUN_3_APPLY_BUILD.cmd`
4. `RUN_4_DIAGNOSTIC.cmd`
5. `RUN_5_TEST_DEMONS.cmd`

Test path: boot to Character Creation, inspect Body Type/Foundation/Appearance, select Player Name, type in the visible `SharpEmu - Text Input` window, press OK, verify the name appears, then try Finalise. Close SharpEmu normally so RUN_5 writes the runtime/result logs and ZIP into `Patches`.

Diagnostic opt-out only: set `SHARPEMU_DS_DCC_EXACT_FORMAT=0` to disable the title-scoped exact-format DCC rule. Default is enabled.
