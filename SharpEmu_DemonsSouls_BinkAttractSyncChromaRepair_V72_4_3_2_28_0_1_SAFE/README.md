# SharpEmu Demon's Souls Bink Attract / Audio / Chroma Repair V72.4.3.2.28.0.1

SAFE source correction on top of V27.0.1/V27.0.2.

V27.0.2 result established:
- native NIHAV was active;
- only ps_studios_logo + logo_intro completed;
- no attract movie was attached;
- external intro audio started but had no attract video to follow;
- the V27 boundary-only chroma repair did not remove the block-wide colour errors.

V28:
- injects attract_movie as the third host fallback movie only for audited
  Demon's Souls installs;
- removes logo_intro_loop from this title-specific host fallback;
- caps the logo segment of external audio at 12 seconds;
- restarts the cached +12s audio tail on attract_movie's first presented frame;
- sets NIHAV priority mode 3 (High);
- replaces edge-only U/V repair with robust whole-block 8x8 bias correction,
  followed by the existing boundary blend;
- does not touch Y/luma;
- preserves the V17 Q14 colour basis and V27 centered neutral gate.

Run in order:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DEMONS_SOULS_TEST.cmd

Close SharpEmu normally after observing the third movie. Send back
SharpEmu_V72_4_3_2_28_BINK_RESULT_<timestamp>.zip.


## V72.4.3.2.28.0.1 package repair

V28's source correction did not begin on the reported run. Both PRECHECK and
APPLY stopped before modification because PowerShell variable names are
case-insensitive and the package used `$host`, which collides with the built-in
read-only `$Host` automatic variable.

V28.0.1 renames that package-local path variable to `$hostBridgePath` in both
precheck and apply/build. The V28 C# payload and intended source correction are
otherwise unchanged.

The package validator now also scans every PowerShell script and rejects any
future assignment to `$host`.

Because V28 never reached its apply stage in the reported run, no V28 rollback
is required before using V28.0.1.
