SharpEmu V76.3.21.2
Global Snapshot Bounds / Loading Crash Recovery — DEV SAFE

CRASH PROVEN IN V21.1
---------------------
The V21.1 diagnostic reached main loop and first frame, but the Vulkan presenter
then unwound with:

System.ArgumentOutOfRangeException
  VulkanVideoPresenter.Presenter.TryPrepareWritableGlobalRefreshV74051(...)
  VulkanVideoPresenter.cs: line 12738

This was not DeviceLost or AccessViolation. The Presenter catches the exception,
the window closes with requested=False, and the mitigated child may still exit
with code 0. V21.1's old diagnostic therefore reported fatal=0 even though the
renderer had functionally crashed.

ROOT CAUSE
----------
TryPrepareWritableGlobalRefreshV74051 validates that the logical range fits in
the persistent Shadow allocation, but then assumes:

    guestBuffer.Data.Length >= guestBuffer.Length

before creating:

    guestBuffer.Data.AsSpan(0, guestBuffer.Length)

V117.12 already introduced the valid concept of a deferred global descriptor:
Data.Length==0 with a positive logical Length. Later residency/deferred-read
work can also expose a PARTIAL snapshot: 0 < Data.Length < Length.

The old code did not recognize that case.

V21.2 FIX
---------
Any global buffer with:

    Length > 0 && Data.Length < Length

is now treated as deferred/live-backed.

1. TryPrepareWritableGlobalRefreshV74051:
   - never creates a Span larger than Data;
   - compares current guest memory directly against the persistent Shadow;
   - keeps the existing nonblocking timeline defer behavior.

2. CreateGlobalBufferResource:
   - generalizes deferredLiveReadV11712 from Data.Length==0 to every partial
     snapshot;
   - existing live guest read becomes the source of truth.

3. CreateVersionedReadOnlyGlobalBufferResource:
   - partial snapshots enter the existing resident/deferred live-read path
     instead of the unsafe staging AsSpan path.

4. Diagnostic:
   - counts "[LOADER][ERROR] Vulkan VideoOut presenter failed" as a renderer
     crash even if child exit code is 0;
   - counts ArgumentOutOfRange separately;
   - records GLOBAL_SNAPSHOT_REPAIR markers;
   - samples NVIDIA utilization/VRAM/power when nvidia-smi is available.

PRESERVED
---------
The package DOES NOT roll back V21.1 performance work:
- dual resource/timeline queues
- V17 async AGC
- compute chain 8
- draw command buffer 32
- ordered microbatch 64
- residency 1536 / 512 MB
- resident shaders 2048
- descriptor cache 4096
- producer query/scan and closure policy
- safe memcpy
- nonblocking global refresh
- WAIT/WRITE_DATA/RELEASE_MEM semantics
- Bink policy

APPLICATION
-----------
This is an adaptive in-place patch. It does not ship a complete
VulkanVideoPresenter.cs and therefore does not overwrite the user's current
V21.1 source.

RUN_3:
- creates a source backup first;
- applies only the three bounds/deferred transformations plus one trace field;
- runs dotnet restore;
- builds Debug / win-x64;
- automatically restores Presenter + CLI on any failure.
