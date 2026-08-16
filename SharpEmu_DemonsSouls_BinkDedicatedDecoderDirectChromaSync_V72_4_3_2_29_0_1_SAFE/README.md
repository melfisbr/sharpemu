# SharpEmu Demon's Souls V72.4.3.2.29.0.1 SAFE

Cumulative correction on top of V28.0.1.

V28 result:
- all 3 movies completed;
- attract was correctly injected and attached;
- no unhandled exception;
- attract_movie nominal duration: 117.367 s;
- measured bridge duration: ~323.40 s (~10.9 effective fps);
- read time stayed around 3.2 ms/frame;
- color conversion stayed around 20.5 ms/frame;
- producer wait rose toward ~900 ms;
- attract audio started from the +12 s tail, but wall-clock audio outran the
  much slower video;
- the visible artifacts remained because exact633 uses the packed PGM payload
  directly, bypassing the planar U/V repair introduced in V27/V28.

V29 corrections:

1. Dedicated decoder CPU affinity
   - after nihav-tool starts, move it to the highest two SYSTEM logical CPUs;
   - this happens after process creation, so it can escape the SharpEmu process
     affinity inherited from the movie gate;
   - SharpEmu remains on the lower movie CPU set;
   - NIHAV remains High priority.

2. Direct exact633 chroma repair
   - replaces the active direct packed 3x3 U/V average with a 7x7 packed
     row-split average;
   - this acts on the real active hot path, unlike the planar-only V27/V28
     repair;
   - luma is unchanged;
   - frame-truth capture is extended deep into attract_movie.

3. Audio rate compensation
   - cached attract +12 s tail is regenerated with FFmpeg `atempo=0.9054`;
   - 0.9054 is 27.162/30 from the user's native/LTO pure decoder benchmark;
   - the cache filename includes V29 and tempo so the old unstretched WAV is
     never reused;
   - environment override: SHARPEMU_DS_ATTRACT_AUDIO_TEMPO (0.75..1.00).

4. Boot delay
   - V29 sets SHARPEMU_BINK_AUTO_BOOT_GRACE_MS=1500 for this path;
   - the V28 result had a very long delay before host movie decoding began.

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DEMONS_SOULS_TEST.cmd

Close SharpEmu normally after observing the attract movie. Send the generated
`SharpEmu_V72_4_3_2_29_BINK_RESULT_<timestamp>.zip`.

Rollback: RUN_ROLLBACK_LAST.cmd


## V72.4.3.2.29.0.1 package repair

V29 PRECHECK incorrectly requested:

`V72.4.3.2.27 REFERENCE_COLOR_CALIBRATED_ROW_SPLIT`

The reference-calibrated row-split implementation was introduced by V17, so
the actual accumulated source marker is:

`V72.4.3.2.17 REFERENCE_COLOR_CALIBRATED_ROW_SPLIT`

V29.0.1 corrects only that prerequisite typo. The V29 source payload remains
unchanged: dedicated NIHAV CPU affinity, exact633 packed chroma7 filtering,
extended attract frame truth, and attract audio rate compensation.

The validator now explicitly requires the V17 marker and rejects the erroneous
V27 spelling.

The failed V29 run never reached source application, so no rollback is needed.
