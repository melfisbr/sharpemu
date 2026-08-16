SharpEmu V74.0.17 SAFE

Purpose
-------
The V74.0.16.1 result disproved DCC alias history as the current startup fix:
64 history seeds, 0 history hits, no natural Bink request, and higher allocation pressure.

The same run reached the import-progress 16,777,216 threshold and saturated the
DBFZ-specific pthread opaque-owner trace almost immediately. That compatibility
layer performs extra guest-memory resolution/read/write after every successful
adaptive mutex lock/unlock. It was introduced for Dragon Ball FighterZ but is
currently paid by Demon's Souls too.

V74.0.17 adds an explicit runtime gate:
  SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC

Default remains ENABLED, preserving all existing games and DBFZ behavior.
The Demon's Souls RUN_4 test sets it to 0 only for that child process.

The test also sets SHARPEMU_DCC_ALIAS_HISTORY_MS=0 because V74.0.16.1 produced
64 seeds and zero hits. The V74.0.16.1 source is preserved; this package does not
remove or overwrite it.

Safety
------
- Structural source patch only; no whole-file payload replacement.
- PRECHECK and APPLY use the exact same structural matcher/transformer.
- Source backup is restored automatically on apply/build failure.
- Release win-x64 build is required before RUN_4.
- Package validation parses every PowerShell script, audits reserved automatic
  variables, verifies every CMD target, manifest coverage and SHA-256 hashes.

Run in order
------------
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_PTHREAD_FASTBOOT.cmd
