# SharpEmu Demon's Souls RAD Bink Player Backend V72.4.3.2.31.2 SAFE

This revision repairs the V31.1 accumulated-checkout failure:

`Anchor ambiguous: same active RAD state`

## What changed

- RAD remains optional.
- If `radvideo64.exe` is **not found**, RUN_3 does **not modify HostMovieBridge.cs** and does not install the unused RAD bridge. It builds the existing V30/V74 fallback baseline instead.
- Existing fallback order is preserved: `native -> NIHAV -> FFmpeg`.
- Existing V30 audio/tempo behavior is preserved when RAD is absent.
- If RAD is available, the duplicated active-state expression is updated at all legitimate occurrences instead of requiring a globally unique anchor.
- The package never redistributes the RAD executable.
- Rollback snapshots are still created before RUN_3.

## Run

```powershell
.\SharpEmu_DemonsSouls_RADBinkPlayerBackend_V72_4_3_2_31_2_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
.\SharpEmu_DemonsSouls_RADBinkPlayerBackend_V72_4_3_2_31_2_SAFE\RUN_2_PRECHECK.cmd
.\SharpEmu_DemonsSouls_RADBinkPlayerBackend_V72_4_3_2_31_2_SAFE\RUN_3_APPLY_BUILD.cmd
.\SharpEmu_DemonsSouls_RADBinkPlayerBackend_V72_4_3_2_31_2_SAFE\RUN_4_DEMONS_SOULS_TEST.cmd
```

When RAD is absent, the expected RUN_3 result is:

`NO SOURCE PATCH REQUIRED: fallback baseline compiled successfully.`
