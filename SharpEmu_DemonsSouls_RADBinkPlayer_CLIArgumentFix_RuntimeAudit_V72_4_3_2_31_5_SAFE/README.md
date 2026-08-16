# SharpEmu V72.4.3.2.31.5 — RAD BinkPlay CLI Argument Fix + Runtime Audit

## What the V31.4 result proved

The result ZIP proved that SharpEmu selected RAD and did **not** use NIHAV:

- `RAD_AVAILABLE=True`
- `ACTIVE_BINK_MODE=rad`
- `RAD_STARTED=3`
- `RAD_ATTACHED=3`
- `NIHAV_OR_INTERNAL_FALLBACK_HITS=0`

However, the RAD processes completed with `exit=1`, and the screenshot showed the BinkPlay
syntax/help dialog. V31.4 therefore did not actually decode the movie.

## Root cause

V31.4 started:

`radvideo64.exe binkplay "<movie.bk2>" /#`

The BinkPlay 2026.06 syntax window shown in the test does not list `/#` as a BinkPlay
switch. V31.5 removes that extra argument and starts:

`radvideo64.exe binkplay "<movie.bk2>"`

## Important architectural point

`radvideo64.exe binkplay` is a **separate executable**. It cannot become SharpEmu's
Vulkan decoder merely because SharpEmu launched it. V31.5 fixes the external-player
proof path, but it intentionally does not claim to be an in-process decoder.

`RUN_6_RAD_RUNTIME_AUDIT.cmd` inventories the installed RAD directory and, when an
export tool is available, records PE exports. Send its ZIP back. That audit tells us
whether the local RAD installation contains a runtime DLL/API that can support a true
in-process SharpEmu backend without redistributing proprietary binaries.

## Run order

1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_PRECHECK.cmd`
3. `RUN_3_APPLY_BUILD.cmd`
4. `RUN_4_RAD_SMOKE_TEST.cmd`
5. `RUN_5_DEMONS_SOULS_TEST.cmd`
6. `RUN_6_RAD_RUNTIME_AUDIT.cmd`

Do not continue to RUN_5 if RUN_4 returns a non-zero exit code or opens the syntax/help
dialog.

## Expected RUN_4 result

The PlayStation Studios movie should actually play in the external BinkPlay window and
the script should finish with:

`RAD_SMOKE_EXIT_CODE=0`
`RAD BINKPLAY SMOKE TEST PASSED.`

## Expected RUN_5 evidence

At minimum:

`bink2.rad_command syntax='radvideo64.exe binkplay <movie>'`
`Bink RAD bridge completed: ... exit=0`
`RAD_COMPLETED_NONZERO=0`
`NIHAV_OR_INTERNAL_FALLBACK_HITS=0`
`STRICT_RAD_CLI_PROOF=True`

## Safety

No RAD/Bink executable or DLL is included in this package.
