# SharpEmu Demon's Souls V74.0.86.1.6 SAFE

This package fixes the two false post-apply failures in V74.0.86.1.5.

Before touching the repository, RUN_1 now proves that:
- the payload carries the exact V86.1.6 Base64 marker;
- the OSK Base64 decodes successfully;
- the embedded PowerShell parses;
- the decoded script contains the title, Done button, player-name prompt, and WinForms form.

Run in order:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd
