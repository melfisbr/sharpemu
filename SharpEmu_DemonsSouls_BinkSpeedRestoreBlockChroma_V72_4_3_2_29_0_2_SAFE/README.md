# SharpEmu Demon's Souls V72.4.3.2.29.0.2 SAFE

Emergency speed restoration on top of the applied V29.

The V29 result proved the slowdown is the new chroma7 converter:

- ps_studios_logo conversion: ~126 ms/frame;
- logo_intro conversion: ~126 ms/frame;
- attract_movie conversion: ~122 ms/frame;
- attract bridge duration: ~1014.86 s for a nominal 117.37 s movie.

The dedicated NIHAV affinity succeeded with zero affinity failures and is kept.

V29.0.2 removes only the expensive 7x7-per-pixel chroma implementation and
replaces it with a 9-sample block-spaced kernel:

- center source chroma position;
- same position in left/right 8x8 blocks;
- same position in up/down 8x8 blocks;
- four diagonal neighbouring blocks.

This is 9 reads per plane — the same read count as the original 3x3 box —
instead of V29's up-to-49 reads per plane. It still crosses the 8x8 chroma
block boundaries that caused the visible colour discontinuities.

Preserved from V29:
- dedicated NIHAV logical CPUs;
- NIHAV High priority;
- native/LTO nihav-tool;
- attract audio tempo 0.9054;
- 1.5 s auto-boot grace;
- extended attract frame-truth capture.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DEMONS_SOULS_TEST.cmd

Close SharpEmu normally after observing the attract movie. Send the generated
SharpEmu_V72_4_3_2_29_0_2_BINK_RESULT_<timestamp>.zip.

Rollback: RUN_ROLLBACK_LAST.cmd
