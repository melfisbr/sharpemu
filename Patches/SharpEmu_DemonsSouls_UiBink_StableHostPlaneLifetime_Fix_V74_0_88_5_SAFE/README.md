# SharpEmu Demon's Souls Stable Host Plane Lifetime Fix V74.0.88.5 SAFE

The V74.0.88.4 log proves the crash occurs inside `vkCmdCopyBufferToImage` while `logo_intro_loop.bk2` is active, before `main_menu.bk2` is reached.

V74.0.88.5 keeps Bluepoint NumberType=4 Y/UV descriptor recognition but no longer lets descriptor NumberType destroy/recreate the host Bink VkImages while translated draws can still reference them.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DIAGNOSTIC.cmd
5. RUN_5_TEST_DEMONS.cmd

Logs and result ZIPs are written directly to `Patches`.
