SharpEmu V74.0.67.2.16.1
RAM + Wait Audit ParamBlock Fix SAFE

CORRECTION OVER V2.16
=====================
V2.16 correctly validated the accumulated runtime/source state, but RUN_4
failed when source_audit.ps1 was invoked with -OutputPath because common.ps1
(Set-StrictMode -Version Latest) was dot-sourced before the script-level
param(...) block.

V2.16.1 moves param(...) before common.ps1 in BOTH parameterized scripts:
- scripts\source_audit.ps1
- scripts\analyze_runtime.ps1

This also prevents the same failure from occurring later in RUN_5.

NO EMULATOR RUNTIME SOURCE CHANGE
=================================
This package does not alter SharpEmu source/runtime behavior. It preserves:
- V2.15 effective RAM TTL=120000 ms
- V2.15 frontend DLSS one-click contract
- V2.14 pre-composite DLSS command-buffer ownership
- V2.13+ RAM/DLSS cumulative source
- BPE recovery chain

RUN ORDER
=========
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DIAGNOSTIC.cmd
RUN_5_OPEN_GUI.cmd

RUN_4 creates the source audit ZIP in Patches.
RUN_5 opens the GUI without forced DLSS shell variables, captures stdout/stderr,
then creates the runtime audit ZIP after SharpEmu closes.

See:
docs\V2161_PARAMBLOCK_ROOT_CAUSE.txt
