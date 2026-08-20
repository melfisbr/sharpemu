SharpEmu V74.0.67.2.16
RAM + Wait Root-Cause Audit SAFE

WHAT THE LATEST RUN PROVES
==========================
1. DLSS is active and stable.
   selected=dlss
   state=active
   dlss_dispatches advances into the 8300s
   dispatch_failures=0

2. V2.15 TTL correction is active.
   ARRAY_CACHE_OWNER reports ttl_ms=120000.

3. The process exits normally.

4. RAM is still high.
   Managed alloc2s_mb remains around 1-2+ GiB in representative samples.
   private_mb remains around 18-21 GiB.

5. The two-entry large-array cache still evicts because several distinct
   64/128/256/320 MiB arrays rotate through it.

WHY V2.16 IS AN AUDIT INSTEAD OF A SPECULATIVE CACHE PATCH
===========================================================
The current log proves cache churn exists, but the number of cache-owner events
is too small to explain the entire managed allocation rate. Increasing the
cache from 2 entries to all observed arrays would retain over 1 GiB of extra
large buffers and conflicts with the RAM-reduction goal.

Likewise, the current log shows repeated 1-2 second WAIT_REG_MEM stalls where
producer_state=completed and producer_completed_after_wait=1, plus saturation
at pending=24. Skipping those waits without inspecting the exact visibility/
wake path could break guest synchronization.

Therefore V2.16 makes NO behavioral/runtime source change. It captures exactly
the source regions and runtime metrics required to make the next correction
without guessing.

RUN_4
=====
Creates a source audit ZIP in Patches with:
- TryGetLargeArraySnapshotV74064
- StoreLargeArraySnapshotV74064
- ARRAY_CACHE_OWNER / ARRAY_CACHE_EVICT source windows
- V2.15 effective TTL source
- SLOW_WAIT_PRODUCER source window
- DEDICATED_WAIT_DRAIN source window
- GATE_OWNER_WAIT_DRAIN source window
- RequestResumableDcbDrain
- PumpSubmittedQueuesV74030
- submission capacity / hard-cap probe source
- every new byte[], GC.AllocateUninitializedArray<byte>, and ToArray() site in
  AgcExports.cs and VulkanVideoPresenter.cs

RUN_5
=====
Opens the GUI without forced DLSS shell variables, captures stdout/stderr,
waits for normal shutdown, analyzes the logs automatically, and creates:

  SharpEmu_V74_0_67_2_16_RUNTIME_AUDIT_<timestamp>.zip

The analysis reports:
- DLSS active/dispatch max/failures
- alloc2s/heap/fragmentation/working/private stats
- guest-image and texture-memory stats
- large-array owner bytes, evictions, distinct keys, TTL
- ratio between cache-owner bytes and sampled managed allocation
- slow wait min/max/average
- completed-producer slow-wait count
- submission hard-cap saturation
- hard-cap fence-probe progress ratio

SEND THE RUNTIME_AUDIT ZIP
==========================
That output is sufficient to choose between:
A) a size-aware bounded cache admission correction,
B) a specific large managed allocation-site reuse correction,
C) a completed-producer wake/visibility correction,
D) submission retirement/capacity correction.

DLSS is deliberately not modified.
