SharpEmu - Demon's Souls FastBoot / Performance / Bink Handoff / Runner Repair V74.0.13.1
======================================================================================

Purpose
-------
This cumulative follow-up to V74.0.12 addresses the exact failures observed in the
2026-08-15 timed run:

1. Multi-minute pre-video bottleneck
   - Prefer Release win-x64 runtime for the timed game run.
   - SHARPEMU_RENDER_SCALE=0.5 for non-storage guest color/depth images.
     A logical 3840x2160 target becomes 1920x1080 physically while storage/UAV
     images remain native, using the presenter's existing scale-aware design.
   - Bounded Vulkan caches during the run:
       sampled guest image 256 MB
       standalone texture 384 MB
       guest buffer 192 MB
       device buffer 384 MB
   - Explicitly disables overlay and ambient full-truth/per-frame diagnostics
     that can remain enabled from earlier audit sessions.

2. First startup movie did not hand control back to the guest
   - Keeps the precise Bink completion parser first.
   - If the precise frame-index parser rejects a valid KB2 startup file, a
     V74.0.13.1 header fallback validates the 16-byte KB2 core header and changes
     only NumFrames to 1 after the real host playback has finished.
   - Limited to ps_studios_logo.bk2 and logo_intro.bk2.
   - logo_intro_loop.bk2 remains guest-controlled.

3. V74.0.12 diagnostic runner defects
   - Fixes PowerShell format-operator precedence that printed {0:F0} literally.
   - Fixes over-escaped natural-movie regexes.
   - Makes the phase deadline extend after the first movie instead of only
     shortening the original deadline.
   - Stops the launcher plus mitigated-child process tree before finalization.
   - Reads stderr.log through FileShare.ReadWrite|Delete with retries, eliminating
     the ReadAllText sharing violation seen in V74.0.12.
   - Preserves the result directory even if ZIP creation itself fails.

Safety / scope
--------------
- No EBOOT bytes are modified.
- No game files are modified.
- The only source file changed by APPLY is:
    src\SharpEmu.Libs\Media\HostMovieBridge.cs
- A timestamped source backup is made under .sharpemu-hotfix-backup.
- If either Debug or Release build fails, HostMovieBridge.cs is restored.
- V74.0.12 presenter/native-lane changes are required and preserved.

Expected EBOOT SHA256
---------------------
22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

Run order from the SharpEmu repository root
--------------------------------------------
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_FASTBOOT_PERF_HANDOFF.cmd

The last command creates:
  SharpEmu_V74_0_13_1_FASTBOOT_PERF_HANDOFF_RESULT_<timestamp>\
and, when compression succeeds:
  SharpEmu_V74_0_13_1_FASTBOOT_PERF_HANDOFF_RESULT_<timestamp>.zip

Key success signals
-------------------
- Numeric status values instead of literal {0:F0} placeholders.
- First natural movie reached substantially sooner than the V74.0.12 run.
- bink2.startup_completion_shim mode=precise OR
  bink2.startup_completion_shim_header_fallback.
- A second natural startup movie, or post-first-movie guest progress.
- RESULT ZIP is printed even after the timed diagnostic stop.
