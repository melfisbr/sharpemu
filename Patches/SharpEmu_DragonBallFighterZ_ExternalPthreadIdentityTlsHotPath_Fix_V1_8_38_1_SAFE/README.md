# SharpEmu Dragon Ball FighterZ — External Root Pthread Identity/TLS Hotpath V1.8.38.1 SAFE

## Root cause from V1.8.37.1 result

V1.8.37.1 recorded zero cooperative APR waits and every sampled APR host wait used `guest=0`.
The top-level guest path explicitly invokes `NativeGuestExecutor.Run(... guestThreadHandle: 0 ...)`.
`KernelPthreadState` nevertheless creates a stable synthetic pthread identity on that raw host thread.

Before V1.8.38, the DirectExecutionBackend pthread hotpath rejected `CurrentGuestThreadHandle == 0`,
so the root executor could not use the already-safe `pthread_self` / `pthread_getspecific` hotpaths.
The sparse import checkpoints remain dominated by these identities/TLS NIDs.

V1.8.38 recovers the existing KernelPthreadState handle only for identity/TLS hot kinds. It does NOT
write `GuestThreadExecution.CurrentGuestThreadHandle`, does NOT promote the root executor into
`_guestThreads`, does NOT enable mutex hotpath, and does NOT change APR/join wait ownership.

## Output

All RUN transcripts, diagnostic logs and result ZIP are written directly to:
`C:\Users\Edpo\Documents\GitHub\sharpemu\Patches`

Result ZIP:
`DBFZ_EXTERNAL_PTHREAD_V1_8_38_1_RESULT_<timestamp>.zip`

## V1.8.38.1 diagnostic/logging repair

This package preserves the already-applied V1.8.38 source fix. It repairs the diagnostic script only:

- removes a Windows PowerShell 5.1 typed-variable collision where `[long]$n` was later reused for string milestone keys such as `Import8M`;
- uses dedicated `$hotCount` and `$milestoneName` variables;
- routes every RUN through `scripts/run_logged.ps1`, which pre-creates and streams all output/errors into `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches` using a Windows PowerShell 5.1-safe streaming `Add-Content` logger;
- `RUN_5` therefore leaves a log even when the diagnostic itself terminates with an error.
