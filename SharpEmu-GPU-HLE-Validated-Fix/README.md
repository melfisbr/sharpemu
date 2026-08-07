# SharpEmu GPU/HLE correction package

## Files replaced

- `src/SharpEmu.Libs/Kernel/KernelPthreadCompatExports.cs`
- `src/SharpEmu.Libs/Kernel/KernelPthreadLibcStartupExports.cs`
- `src/SharpEmu.Libs/Agc/GpuWaitRegistry.cs`
- `src/SharpEmu.Libs/Agc/AgcExports.cs`

## Corrections

### pthread/HLE

The reduced pthread replacement from the supplied archive was replaced by the
complete current SharpEmu implementation. It restores:

- adaptive, normal, recursive and error-check mutex semantics;
- guest-owner tracking and host-thread contention;
- alias/slot handle resolution;
- condition waiter queues and `SignalEpoch`;
- `pthread_cond_wait` (`Op8TBGY5KHg`) and the scePthread aliases;
- once, mutex attributes and condition attributes;
- scheduler-aware blocking without removing the host-side behavior required by
  the existing unit tests.

`KernelPthreadLibcStartupExports.cs` is intentionally an empty compatibility
shim because all of its former NIDs are already owned by the complete pthread
implementation. This prevents duplicate export registration.

### AGC/GPU synchronization

- `RecordProduced` now updates producer history and latches already-existing
  waiters under one lock.
- Added typed watched-label range snapshots.
- WRITE_DATA records every produced dword and final overlapping 64-bit labels.
- DMA_DATA records watched labels after deferred image-mirror completion.
- RELEASE_MEM records actual timestamp values for timestamp data selections.
- Fixed pooled compute-evaluation arrays not being returned when GPU dispatch
  creation fails.

## Applying

From the extracted package directory:

```powershell
.\apply_and_validate.ps1 -RepositoryRoot "C:\Users\Edpo\Documents\GitHub\sharpemu"
```

The script creates a timestamped backup under `artifacts\backup-gpu-hle-*`,
applies the files, runs `dotnet build`, then runs Libs and ShaderCompiler tests.

## Runtime test

```powershell
.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
  "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
  --log-level=debug `
  --log-file=gpu_after_gpu_hle_fix.txt
```

Useful searches:

```powershell
Select-String .\gpu_after_gpu_hle_fix.txt -Pattern `
  "Op8TBGY5KHg|agc.wait_|agc.queue_resumed|agc.dcb.draw|shader|SPIR-V|Draw Calls"
```
