SharpEmu Demon's Souls JobSystem sceKernelUsleep Scheduler Fix V73.10 SAFE

V73.9 RESULT
- all 8 audited native UI ranges sampled 0 times;
- real VideoOut present counter was positive in all 39 sampled windows;
- max presented FPS = 20.8;
- submitted_fps remained 0 in the captured windows;
- unresolved imports = 0;
- deviceLost = 0;
- auto Options was configured but the run ended before a press sample was produced.

CPU HOTSPOT FROM THE EBOOT
V73.9 guest profiling places 78.5%..96.4% of sampled guest
execution on app page 0x821000. Direct EBOOT disassembly proves the hot routine:
  bpe::threading::JobSystemScheduler::WaitForJobs()
  app 0x820FE0..0x821220

The routine performs 10,000 PAUSE iterations and calls app+0x827080, which is
a thunk to PLT NID 1jfXLRVzisc = sceKernelUsleep.

SHARPEMU SEMANTIC GAP
DirectExecutionBackend currently supplies sceKernelUsleep as a native leaf
intrinsic. That intrinsic yields/sleeps on the host but bypasses the managed HLE
handler.

KernelRuntimeCompatExports.KernelUsleep contains:
  GuestThreadExecution.Scheduler?.Pump(ctx, "sceKernelUsleep");

Thus the title's dominant scheduling primitive was skipping SharpEmu's guest
scheduler pump.

V73.10 FIX
IsHlePreferredNid now returns true for NID 1jfXLRVzisc. This prevents the native
intrinsic and direct leaf paths from taking ownership, routing sceKernelUsleep
through the existing HLE implementation and its scheduler Pump.

No EBOOT bytes are modified.
No wait values are fabricated.
No GPU synchronization rule is changed.
The native intrinsic is left in source but is no longer selected while HLE
preference is active.

Exact current source guard:
  DirectExecutionBackend.cs
  5BD0229D97C3862EDC5736D65E41BE3F062A5B9D31B5396EE28F58086D4B1DA8

DIAGNOSTIC
The script automatically runs for at most 130 seconds and then stops the
emulator. It enables sampled usleep tracing, the existing V73.9 UI RIP probe,
real VideoOut FPS counting and Options edges at 70/80/90/100/110/120 seconds.

It compares the JobSystem app+0x821000 share against V73.9's 91.2% peak and
reports whether UIManager or StartMenu native methods become reachable.

Result:
  SharpEmu_V73_10_JOB_UI_RESULT_<timestamp>.zip
