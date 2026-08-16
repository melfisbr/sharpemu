# SharpEmu Demon's Souls Optional RAD Bink Backend V72.4.3.2.31.1 SAFE

This revision fixes V72.4.3.2.31's setup deadlock when `radvideo64.exe` is not installed.

Key behavior:
- RAD Video Tools is OPTIONAL.
- If `radvideo64.exe` is found, `radvideo64.exe binkplay <movie.bk2>` is primary.
- If RAD is absent, build/apply still succeeds and the runtime uses `native -> NIHAV -> FFmpeg`.
- The existing V30 Demon's Souls attract audio/tempo is preserved when RAD is absent.
- No RAD executable, Bink DLL, or Bink SDK binary is redistributed.
- The external RAD bridge no longer waits up to 5 seconds for `WaitForInputIdle`.
- Discovery checks environment/config, PATH, running process, Windows RAD/.bk2 registration, common install folders, and only then shallow Downloads/Desktop locations.
- Discovery avoids recursively walking all of Downloads/Desktop.
- A valid local RAD path is stored only when RAD actually exists.

Run:
1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_PRECHECK.cmd`
3. `RUN_3_APPLY_BUILD.cmd`
4. `RUN_4_DEMONS_SOULS_TEST.cmd`

Expected without RAD:
- PRECHECK PASSED
- `RAD player: not found (OPTIONAL)`
- build succeeds
- test starts with `ACTIVE_BINK_MODE=native`
- NIHAV remains the expected Bink2 fallback

Expected with RAD:
- RAD path/hash shown in precheck
- build succeeds
- test starts with `ACTIVE_BINK_MODE=rad`
- RAD process owns Bink playback and NIHAV remains fallback

The official RAD executable is not included in this package.
