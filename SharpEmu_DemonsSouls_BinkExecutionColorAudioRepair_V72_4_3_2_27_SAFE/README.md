# SharpEmu Demon's Souls Bink Execution / Color / Audio Repair
## V72.4.3.2.27 SAFE

This is a cumulative **source correction**, not a script-only probe.

### Validated input

The accumulated Demon's Souls audit established:

- `logo_intro.bk2` pure NIHAV decoding can exceed 30 fps, but PGMYUV frame
  export cuts the effective path to roughly 26 fps.
- the user-benchmarked `target-cpu=native + fat LTO` NIHAV executable improves
  pure decode by about 10–11%;
- the direct RAW PGMYUV truth is `P5 3840 3240 255`;
- Y is clean while rectangular discontinuities are already present in U/V;
- the V17 row-split Q14 calibration is the closest validated color basis;
- V21/V22's neutral gate interprets already-centered Cb/Cr as if they were
  unsigned and subtracts 128 again;
- the eboot starts opening video and intro music through separate state-machine
  paths;
- the game's cutscene banks resolve the external opening stems to:
  - `pr_demons_souls_intro_music.at9`
  - `pr_demons_souls_intro_sfx.at9`
  - `pr_demons_souls_intro_vo.at9`
- the three external streams are ~129.433 s; `logo_intro` + `attract_movie`
  matches that continuous timeline to within about two 30-fps frames.

### Corrections installed

1. **Execution / pacing**
   - deploys the already benchmarked native/LTO `nihav-tool.exe`;
   - uses a 60-frame startup reservoir;
   - raises stream prefetch timeout to 8 s;
   - disables stale-frame clock-catchup deletion (`MAX_CATCHUP_SKIP=0`);
   - defaults Bink presentation conversion to 640x360;
   - preserves streaming mode and realtime deadline;
   - does not touch the guest scheduler, event park, Vulkan queue logic, or
     Core/Libs dependency graph.

2. **Color / artifacts**
   - keeps verified NihAV PGMYUV row-split geometry;
   - preserves the V17 Q14 reference calibration;
   - fixes the V21/V22 neutral-gate signed/centered Cb/Cr domain bug;
   - adds an 8x8 chroma-boundary repair only to U/V;
   - never modifies the luma plane;
   - defaults the conservative boundary threshold to 24;
   - scopes the repair to the audited Demon's Souls content.

3. **Audio**
   - preserves the V24 first-presented-frame synchronization hook;
   - prewarms the real external intro AT9 stems while `ps_studios_logo.bk2`
     is playing;
   - caches a 48-kHz stereo WAV mix under LocalAppData;
   - starts the full timeline on the first presented frame of `logo_intro`;
   - continues that timeline into `attract_movie` when it follows directly;
   - if `attract_movie` starts independently, uses a cached audio tail from
     12.000 seconds;
   - cancels stale embedded-audio generations so a late extraction cannot
     overwrite the opening timeline.

### Safety

`RUN_3_APPLY_BUILD.cmd` creates a complete backup under:

`.sharpemu-hotfix-backup\BinkExecutionColorAudio_V72_4_3_2_27_<timestamp>`

If source patching or build fails, the package automatically restores the
previous source files and the previous `nihav-tool.exe`.

`RUN_ROLLBACK_LAST.cmd` manually restores the most recent V27 backup.

### Run order

From the SharpEmu repository root:

1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_PRECHECK.cmd`
3. `RUN_3_APPLY_BUILD.cmd`
4. `RUN_4_DEMONS_SOULS_TEST.cmd`

The test script never force-kills the emulator. Close SharpEmu yourself after
checking the boot videos/title; it then creates a result ZIP in the repository
root.

### Runtime controls

- `SHARPEMU_BINK_CHROMA_DEBLOCK=0` disables the V27 U/V repair.
- `SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD=4..48` adjusts the conservative
  boundary threshold (default 24).
- `SHARPEMU_DS_INTRO_EXTERNAL_AUDIO=0` disables the external intro timeline.
- Existing explicit environment values still override module defaults.

### Known remaining architectural limitation

V27 removes the most disruptive short-movie timing deficit by buffering and
uses the faster native tool, but it does not claim that every high-complexity
4K segment of the 117-second `attract_movie.bk2` is decoded above 30 fps.
The pure decoder benchmark measured difficult portions below realtime even
before PGMYUV staging. A future codec-level/direct-frame transport improvement
can further reduce that cost without changing the V27 audio/color contract.
