# SharpEmu Demon's Souls RAD Bink Player Backend V72.4.3.2.31 SAFE

V31 uses the user's own official RAD Video Tools player as the primary Bink
backend instead of reconstructing Bink2 through NihAV.

The package does NOT include or redistribute radvideo64.exe, any Bink DLL, or
the Bink SDK.

The integration calls:

    radvideo64.exe binkplay <movie.bk2>

SharpEmu tracks the process lifetime and keeps the movie queue/guest completion
gate active until the RAD player exits.

Behavior:
- MovieMode.Rad added;
- default SHARPEMU_BINK_MODE=rad;
- NIHAV/FFmpeg remain fallback if RAD cannot start;
- three-movie Demon's Souls chain remains:
  ps_studios_logo -> logo_intro -> attract_movie;
- RAD owns its own playback window while the movie is playing;
- embedded Bink audio is handled by RAD;
- Demon's Souls external logo/attract AT9 audio remains handled by SharpEmu;
- attract audio tempo is restored to 1.0000;
- old NIHAV color/deblock/conversion path is bypassed whenever RAD succeeds.

Discovery:
1. SHARPEMU_RADVIDEO64
2. PATH
3. running radvideo64.exe
4. Program Files
5. Downloads/Desktop during package setup

After build, only the local path is stored at:
artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path

Run:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_DEMONS_SOULS_TEST.cmd

Expected:
RAD_STARTED=3
RAD_ATTACHED=3
RAD_COMPLETED=3
NIHAV_FALLBACK_ATTACHES=0
RAD_ERRORS=0

A true in-process texture/window integration would require the licensed Bink
SDK. V31 intentionally uses the official player executable already present on
the user's machine instead.
