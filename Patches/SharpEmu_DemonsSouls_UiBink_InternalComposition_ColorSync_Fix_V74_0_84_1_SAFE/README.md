# SharpEmu Demon's Souls UI Bink Internal Composition Color/Sync Fix V74.0.84.1 SAFE

V74.0.84.1 corrects the Windows PowerShell parser failure in the first V74.0.84 package and hardens RUN_5 against stale-binary tests.

This patch is cumulative over the current V74.0.77.2 + V74.0.81/V82 + V74.0.83 title path.

It fixes the next proven boundary: `main_menu.bk2` was still being launched as an external RAD owner movie, which hard-gated the live guest UI. V74.0.84.1 keeps fullscreen startup movies on RAD but routes composited UI Binks (`logo_intro_loop.bk2`, `main_menu.bk2`, `main_menu_ngp.bk2`) through the internal NIHAV texture path.

It also normalizes the Demon's Souls UI-Bink chroma plane to VU by default. To A/B the old order without rebuilding, set `SHARPEMU_DS_UI_BINK_CHROMA_ORDER=uv`.

Run from `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches` in order: validate, precheck, apply/build, diagnostic, test. Logs and result ZIPs are written directly to `Patches`.

`RUN_5_TEST_DEMONS.cmd` is Windows PowerShell 5.1 compatible and deliberately does not use `ProcessStartInfo.ArgumentList`.
