# SharpEmu Demon's Souls VEH Safe Host Read V74.0.88.6 SAFE

The V88.5 runtime crashes before Bink rendering. The managed fatal stack is
`VectoredHandler -> TryReadHostQword -> Marshal.ReadInt64` while handling a
guest `Core.Res.Decompressor` execute AV at RIP 0.

Run in order:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd

All logs/result ZIPs are written to the repository `Patches` directory.
