# DBFZ Worker Ownership Snapshot/Fix V1.8.19 SAFE

V1.8.18 proved that increasing NativeWorkerMaxConcurrent from 16 to 32 did not
allow any guest thread created at n>=15 to execute and slightly worsened splash
time. This package rolls the ineffective experiment back to cap=16 and prewarm=8.

The diagnostic enables the scheduler's existing guest-thread snapshot facility.
Snapshots capture State, ExecutorActive, import count, last NID, block/wake
reason, managed host thread id and native host tid.

Interpretation:
- Ready + executor=False: claim/dispatch problem.
- Running + executor=True with host_tid=0: GuestExecutionRunner/host-start problem.
- Running + executor=True with host_tid set but no imports: native executor entry/acquisition problem.
- Blocked: guest wait semantics rather than worker starvation.

No Vulkan, pthread, import ABI, SharePlay or Pad behavior is changed.
