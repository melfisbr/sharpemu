SharpEmu V76.3.18.5
Adaptive Full Performance Merge — RPCS3-safe / DEV SAFE

WHY THIS PACKAGE IS ADAPTIVE
============================
The V18.0 sequence correctly refused to overwrite the user's current
VulkanVideoPresenter.cs because the actual SHA is:

  0fbac93116b63afd82cd921fa57c8bdfcd57623b1ede0ff568fcab9c355e7a25

This package uses that exact current SHA as its first-run guard but does NOT
ship or replace a complete Presenter. It edits only two bounded pool constants
and appends one authoritative Demon's Souls profile block.

MERGED IMPROVEMENTS
===================
1. Real dual physical Vulkan queue requested; Presenter capability-checks:
   queue count >= 2 + compute + timeline semaphore.
2. Existing byte-range cross-queue hazard tracker/timelines retained.
3. Async AGC V17.0.1 retained.
4. Compute Chain4 retained.
5. Command-buffer recycle pool >= 256.
6. Fence recycle pool >= 256.
7. Producer slices 8x128 retained.
8. Dedicated wait drain + fast-only + submit-evidence wake retained.
9. Producer-less full scan relaxed 16 -> 32 ms by default.
   Emergency compatibility: SHARPEMU_V763185_WAIT_SCAN_16MS=1.
10. Failed V16 host sideband stays OFF; ordered microbatch stays ON.
11. Shader globals remain DEVICE_LOCAL-capable and hot-admitted.
12. Global residency expands:
      max entries 512 -> 1024
      budget      256 -> 512 MiB
    The V17.1 run saturated 512 entries at ~206 MiB and then emitted thousands
    of budget fallbacks, so this is evidence-driven rather than arbitrary VRAM
    reservation.
13. Descriptor-set cache max 4096.
14. Resident shader max 2048.
15. Parallel Vulkan shader-stage compile enabled.
16. SPIR-V prewarm 512 shaders / 128 MiB.
17. Vulkan host-buffer cache 256 MiB.
18. Pipeline-cache periodic save 600s.
19. CPU topology remains compact: native16 / renderer8.
20. Normal gameplay trace/profiling defaults OFF.
21. Safe memcpy V15.1 preserved.
22. Bink strict-resource scope preserved.
23. queue 192/96, burst4, inflight16, lanes6 preserved.

NOT DONE IN THIS REVISION
=========================
- No third/dedicated transfer queue family: that requires ownership transfers.
- No barrier weakening.
- No fake WAIT completion.
- No force-reserving VRAM.
- No HostOnly sideband reordering.
- No full-scan removal: it remains a compatibility watchdog.

EMERGENCY A/B
=============
Force old single physical queue:
  $env:SHARPEMU_V763185_FORCE_SINGLE = "1"

Restore 16ms producer-less waiter scan:
  $env:SHARPEMU_V763185_WAIT_SCAN_16MS = "1"

BUILD
=====
Debug / win-x64.
RUN_3 creates a PRE_SOURCE ZIP and rolls Presenter + Agc + CLI back on any
transform/restore/build failure.

NORMAL PERFORMANCE
==================
RUN_5_NORMAL_PERFORMANCE_LAUNCH.cmd starts the Debug build without diagnostic
profiling/tracing, so Task Manager / NVIDIA utilization can be compared against
the diagnostic run.
