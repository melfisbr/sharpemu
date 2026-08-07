# Static validation report

The execution environment used to prepare this archive does not contain the .NET SDK, so `dotnet build` and xUnit were not executed here. The included PowerShell script performs those checks on the user's machine.

- `src/SharpEmu.Libs/Kernel/KernelPthreadCompatExports.cs`: lexical delimiters balanced.
- `src/SharpEmu.Libs/Kernel/KernelPthreadLibcStartupExports.cs`: lexical delimiters balanced.
- `src/SharpEmu.Libs/Agc/GpuWaitRegistry.cs`: lexical delimiters balanced.
- `src/SharpEmu.Libs/Agc/AgcExports.cs`: lexical delimiters balanced.
- Explicit SysAbiExport NIDs scanned: 1116.
- Duplicate explicit NIDs after replacement: 0.

## Required pthread NIDs
- `Op8TBGY5KHg` / `pthread_cond_wait`: 1 registration(s).
- `tn3VlD0hG60` / `scePthreadMutexUnlock`: 1 registration(s).
- `9UK1vLZQft4` / `scePthreadMutexLock`: 1 registration(s).
- `cmo1RIYva9o` / `scePthreadMutexInit`: 1 registration(s).
- `mkx2fVhNMsg` / `pthread_cond_broadcast`: 1 registration(s).
- `JGgj7Uvrl+A` / `scePthreadCondBroadcast`: 1 registration(s).

## Referenced API compatibility
- `SharpEmu.HLE/GuestThreadExecution.cs` contains `ComputeDeadlineTimestamp`: True.
- `SharpEmu.HLE/GuestThreadExecution.cs` contains `CurrentGuestThreadHandle`: True.
- `SharpEmu.HLE/GuestThreadExecution.cs` contains `GuestThreadAbandoned`: True.
- `SharpEmu.HLE/GuestThreadExecution.cs` contains `IsGuestThread`: True.
- `SharpEmu.HLE/GuestThreadExecution.cs` contains `RequestCurrentThreadBlock`: True.
- `SharpEmu.HLE/GuestThreadExecution.cs` contains `Scheduler`: True.
- `SharpEmu.HLE/GuestThreadExecution.cs` contains `TryGetCurrentImportCallFrame`: True.
- `SharpEmu.Libs/Kernel/KernelPthreadState.cs` contains `DescribeThreadHandle`: True.
- `SharpEmu.Libs/Kernel/KernelPthreadState.cs` contains `GetCurrentThreadHandle`: True.
- `SharpEmu.Libs/Kernel/KernelPthreadState.cs` contains `GetCurrentThreadUniqueId`: True.

## pthread semantic markers
- `SignalEpoch`: True.
- `WaiterQueue`: True.
- `StaticAdaptiveMutexInitializer`: True.
- `MutexTypeRecursive`: True.
- `MutexTypeErrorCheck`: True.
- `TryResolveMutexState`: True.
- `PthreadCondWait`: True.
- `PthreadCondSignal`: True.

## AGC correction markers
- `SnapshotWatchedLabelsInRange` occurrences: 1.
- `LatchSatisfiedByValueLocked` occurrences: 3.
- `RecordProducedLabelsInRange` occurrences: 4.
- `producerCompletionAction` occurrences: 4.
- `evaluationHandledByCpu || !gpuDispatch` occurrences: 1.

## Additional safety checks
- `DMA producer callbacks are success-gated`: True.
- `Standard RELEASE_MEM failure logging is limited to expected guest-memory writes`: True.
