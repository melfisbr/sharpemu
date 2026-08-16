# SharpEmu Demon's Souls V72.4.3.2.30 SAFE

Based on the V29.0.2 runtime result and direct RAW/reference alignment.

V29.0.2 result:
- block9 active;
- conversion ~37 ms/frame;
- dedicated NIHAV affinity active;
- attract still progressively starved after the initial queue;
- audio at 0.9054 ran ahead of the presented video;
- V17 logo-calibrated matrix left attract_movie strongly blue;
- block artifacts remained.

V30:
1. removes block9 entirely and restores the original exact633 3x3 chroma
   average (9 reads/plane);
2. keeps dedicated NIHAV CPU affinity and native/LTO tool;
3. applies a separate direct RGB Q14 matrix only to attract_movie;
4. the attract matrix was fitted from the direct RAW frame containing
   "On the second day" to the matching frame in the supplied reference video;
5. ps_studios_logo/logo_intro keep the V17 + centered-neutral path;
6. changes attract audio tempo from 0.9054 to 0.7000;
7. uses a new `from12-v30-...wav` cache name, so the old audio is not reused;
8. preserves extended attract frame-truth capture.

The color matrix corrects the large global blue/cyan bias. It cannot make
NihAV's incomplete Bink2 reconstruction bit-exact; the upstream decoder still
has known reconstruction/deblocking limitations.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DEMONS_SOULS_TEST.cmd

Close SharpEmu normally after observing attract. Send:
SharpEmu_V72_4_3_2_30_BINK_RESULT_<timestamp>.zip
