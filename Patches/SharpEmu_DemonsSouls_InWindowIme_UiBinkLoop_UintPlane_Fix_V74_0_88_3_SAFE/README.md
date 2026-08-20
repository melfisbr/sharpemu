# SharpEmu Demon's Souls V74.0.88.3 SAFE

Follow-up to V74.0.88.2 for the post-intro stall and the RUN_5 temp-log sharing violation.

This is a delta package. V74.0.88.2 must already be installed.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd

RUN_5 writes the final runtime log live to the Patches directory. There are no temporary redirected stderr/stdout files to read after process exit.
