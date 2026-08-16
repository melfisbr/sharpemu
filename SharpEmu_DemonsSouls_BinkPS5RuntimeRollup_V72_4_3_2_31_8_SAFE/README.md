# SharpEmu Demon's Souls — Bink PS5 Runtime Rollup V72.4.3.2.31.8

This package is the cumulative follow-up to V31.7.3.  It is based on the exact
Demon's Souls EBOOT SHA-256 `22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E` and the successful embedded RAD result.

## What the EBOOT proves

The executable contains string-level evidence for `PS5BinkManager.cpp`,
`HBINK`, `Bink IO`, `Bink Snd`, `frame_bufs[%d].Plane_%s`, BinkGPU, Bink color
correction and the game's Bink movie components.  That is consistent with a
PS5-specific statically linked Bink integration; a Windows `bink2w64.dll` is
not expected in the game directory.

No proprietary Bink code is extracted or redistributed by this package.

## Runtime correction

V31.8 keeps the locally installed official RAD decoder as the decode/color
owner and turns SharpEmu into the presentation host:

1. normal SharpEmu launches automatically select `SHARPEMU_BINK_MODE=rad` only
   when a valid local `radvideo64.exe` is already configured;
2. explicit user Bink mode overrides still win;
3. every BK2 is profiled from its header before launch;
4. SharpEmu does **not** perform the old NIHAV -> BGRA YUV/color conversion in
   RAD mode;
5. the RAD renderer HWND is still required to become a verified child of the
   SharpEmu SDL window — an external desktop player is rejected/killed;
6. child sizing now preserves the movie aspect ratio and is centered; set
   `SHARPEMU_RAD_STRETCH=1` only if full-window stretching is desired;
7. Demon's Souls attract audio keeps the existing AT9 sidecar synchronization
   for the zero-audio-track `attract_movie.bk2` case;
8. the diagnostic requires three PS5 runtime-profile markers, three verified
   embedded attaches, three aspect-fit markers, no NIHAV fallback and no
   SharpEmu BGRA conversion path.

## Files changed

- `src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs`
- `src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs`
- `src\SharpEmu.Libs\Media\BinkPs5RuntimeProfileV724323180.cs` (new)
- `src\SharpEmu.Libs\Media\BinkRadAutoSelectV724323180.cs` (new)
- local `plugins\bink2\radvideo64.path` configuration

The package includes validation, precheck, EBOOT evidence audit, apply/build,
Demon's Souls runtime diagnostic and rollback.  It does not include RAD Video
Tools, Bink DLLs, SDK objects, game media, AT9 or WAV files.
