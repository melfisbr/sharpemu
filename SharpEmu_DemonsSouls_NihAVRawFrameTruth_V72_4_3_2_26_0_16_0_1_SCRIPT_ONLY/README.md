# SharpEmu Demon's Souls NihAV Raw Frame Truth V72.4.3.2.26.0.16

SCRIPT-ONLY. No source changes and no build.

The preceding export benchmark proved that the PGM staging path alone can
reduce a fast pure decode below 30 fps. This package addresses the independent
visual defect: colors and block artifacts.

It captures two **direct NihAV PGMYUV outputs before SharpEmu touches them**:

- `logo_intro` around t=4 s
- `attract_movie` around t=30 s

Only one representative PGM from each short seek window is retained. Temporary
frames are deleted. Each retained file is approximately 12.4 MB for the
3840x2160 Bink2 source.

Send the generated result ZIP back. The raw Y/U/V layout can then be decoded
offline and compared with the existing reference frames. This determines
whether artifacts originate inside NihAV or inside SharpEmu's PGMYUV/color
conversion.

Run:
1. RUN_VALIDATE_PACKAGE.cmd
2. RUN_CAPTURE_RAW_FRAME_TRUTH.cmd


## V72.4.3.2.26.0.16.0.1 — validator repair

V16's validator incorrectly required literal strings
`logo_intro_t4_RAW.pgm` and `attract_t30_RAW.pgm`.

The runner intentionally creates those names dynamically with:

`$test.Name + "_RAW.pgm"`

V16.0.1 validates the two test names and the dynamic output-name expression
instead. The capture algorithm and NihAV command line are unchanged.

No SharpEmu source, NihAV source, or deployed binary is modified.
