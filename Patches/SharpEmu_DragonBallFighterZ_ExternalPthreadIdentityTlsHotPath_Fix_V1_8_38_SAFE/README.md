# SharpEmu Dragon Ball FighterZ — External Root Pthread Identity/TLS Hotpath V1.8.38 SAFE

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
`DBFZ_EXTERNAL_PTHREAD_V1_8_38_RESULT_<timestamp>.zip`
