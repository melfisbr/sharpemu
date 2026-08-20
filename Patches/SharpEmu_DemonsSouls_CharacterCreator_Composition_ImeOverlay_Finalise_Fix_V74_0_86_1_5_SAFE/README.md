# SharpEmu Demon's Souls V74.0.86.1.5 SAFE

Corrects the V74.0.86.1.4 post-apply false negative.

The OSK remains UTF-16LE Base64. The installer now decodes that payload when it needs to verify UI strings such as `SharpEmu - Text Input` and `Done`, instead of incorrectly searching for those strings in the C# source.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd
