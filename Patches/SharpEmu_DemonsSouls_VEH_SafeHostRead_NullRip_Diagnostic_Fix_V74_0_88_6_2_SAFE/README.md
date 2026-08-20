# SharpEmu Demon's Souls V74.0.88.6.2 SAFE

Corrects the C# unsafe-context build failure from V74.0.88.6.1.

The previous package rolled back automatically after the build failure.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd

Expected new RUN_4 marker:
`unsafe_method_declaration=True`

All build/runtime/result logs remain under the repository `Patches` directory.
