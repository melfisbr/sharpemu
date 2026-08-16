SharpEmu V74.0.19 SAFE — Demon's Souls boot-sequence restore

ROOT CAUSE CONFIRMED FROM V74.0.18
- V74.0.18 explicitly set SHARPEMU_BINK_AUTO_BOOT=0 and grace=900000 ms.
- The game main loop started at 18.096 s and GatherResourceFileInfo completed at 32.698 s.
- The first natural startup movie (ps_studios_logo.bk2) did not arrive until host t=373.7 s.
- That movie completed, then the guest returned to compute/render work and did not request the second intro movie before the 605 s deadline.
- Older known-good traces used direct auto boot before guest presentation.
- A two-intro sequence (ps_studios_logo.bk2 -> logo_intro.bk2) is known to complete and restore guest presentation.
- Another accumulated build auto-discovered a third transitional clip (logo_intro_loop.bk2); V74.0.19 accepts it when the current source discovers it.

WHAT V74.0.19 DOES
- Restores SHARPEMU_BINK_AUTO_BOOT=1.
- Restores the historical 1500 ms discovery grace.
- Disables the natural-request completion shim during host-managed direct boot.
- Keeps V74.0.18 native memcpy, render_scale=1.0, TBB=2, renderer/resource lane=8,
  768 MB standalone texture cache, V74.0.15 large-array single-flight, and DCC history disabled.
- Does NOT patch HostMovieBridge: the current source is prechecked for its existing auto/direct-boot machinery.
- Stops after 60 s if direct boot never starts instead of wasting 5–10 minutes in the wrong guest state.
- After direct boot completes, observes guest UI/render for 120 s and packages the result.

ACCEPTED INTRO ORDER
1. ps_studios_logo.bk2
2. logo_intro.bk2
3. logo_intro_loop.bk2 only when the current HostMovieBridge discovers it
Then: bink2.direct_boot_completed ... guest presentation restored.

The runner accepts both the historically successful two-intro handoff and the
three-intro variant. It rejects a reordered sequence.

RUN ORDER
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_BOOT_SEQUENCE_RESTORE.cmd
