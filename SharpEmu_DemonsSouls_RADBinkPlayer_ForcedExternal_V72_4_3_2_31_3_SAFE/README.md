# SharpEmu Demon's Souls RAD Bink Player Forced External V72.4.3.2.31.3 SAFE

This revision exists to prove and enforce the real official RAD playback path.

The V31.2 result showed:

- `RAD_AVAILABLE=False`
- `RAD_STARTED=0`
- `RAD_ATTACHED=0`
- `NIHAV_FALLBACK_ATTACHES=3`

So the corrupted colors / horizontal artifacts / high CPU / audio drift were still coming from the NIHAV conversion path, not from RAD Video Tools.

## V31.3 policy

- `radvideo64.exe` is **required** for RUN_2, RUN_3 and RUN_4.
- Discovery checks `SHARPEMU_RADVIDEO64`, the SharpEmu path cache, PATH, App Paths, running processes, `.bk2` file association, installed-program records, Start Menu shortcuts, Program Files/LocalAppData, and recursive Downloads/Desktop/Documents/tool folders.
- Runtime mode is forced to `rad`.
- RAD mode has **no NIHAV/FFmpeg fallback**.
- SharpEmu sidecar WAV/audio is not started in RAD mode; RAD owns both embedded Bink audio and playback timing.
- The official command is `radvideo64.exe binkplay <movie.bk2> /#` so the player exits automatically when playback finishes and the queued startup sequence can advance.
- The RAD executable is never redistributed by this package.

## Expected visual behavior

For this proof revision the movie is rendered by the external RAD player window. Seeing the old movie frames inside SharpEmu means RAD was not actually active and RUN_4 will classify the run as failed.

## Run

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu

.\SharpEmu_DemonsSouls_RADBinkPlayer_ForcedExternal_V72_4_3_2_31_3_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
.\SharpEmu_DemonsSouls_RADBinkPlayer_ForcedExternal_V72_4_3_2_31_3_SAFE\RUN_2_PRECHECK.cmd
.\SharpEmu_DemonsSouls_RADBinkPlayer_ForcedExternal_V72_4_3_2_31_3_SAFE\RUN_3_APPLY_BUILD.cmd
.\SharpEmu_DemonsSouls_RADBinkPlayer_ForcedExternal_V72_4_3_2_31_3_SAFE\RUN_4_DEMONS_SOULS_TEST.cmd
```

If RUN_2 cannot locate RAD, it intentionally stops and writes:

`RAD_DISCOVERY_V72_4_3_2_31_3.txt`

If you know the executable path, set it explicitly for the current PowerShell session:

```powershell
$env:SHARPEMU_RADVIDEO64 = 'C:\path\to\radvideo64.exe'
```

Then rerun RUN_2.
