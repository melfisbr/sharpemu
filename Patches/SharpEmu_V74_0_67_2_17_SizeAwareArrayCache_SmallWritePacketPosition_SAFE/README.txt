SharpEmu V74.0.67.2.17
Size-Aware Array Cache + Small WRITE_DATA Packet Position SAFE

RUNTIME EVIDENCE
================
The V2.16.1 run proves:
- DLSS is active from the frontend path.
- V2.15 TTL=120000 is working.
- The large-array bridge cache still has only 2 entries and rotates at least
  seven distinct 64/127/256/320 MiB-class resources.
- large-array owner materializations in the supplied runtime total multiple GiB.
- managed allocation remains around 0.6..2.4 GiB per 2-second sample.
- all sampled pathological SLOW_WAIT_PRODUCER events resolve to a completed
  WRITE_DATA producer on another logical queue.
- the Vulkan presenter repeatedly reaches pending=24; that hard cap is NOT
  changed by this package.

RAM FIX
=======
V74.0.64 evicts the oldest of two cached arrays regardless of size. The runtime
shows small 64 MiB arrays repeatedly evicting 256/320 MiB arrays, which then have
to be rematerialized into the LOH.

V2.17 preserves the existing cache entry count and TTL. When the cache is full:
- a new smaller/equal snapshot is used for the current upload but is NOT cached;
- a larger snapshot replaces the smallest cached snapshot;
- stale content generations of the same resource are removed first.

This cannot increase the number of cached array entries. It optimizes which two
entries consume the already-existing bounded cache budget.

WAIT FIX
========
The supplied slow waits are tiny WRITE_DATA label writes (8 bytes in the
measured cases) feeding cross-queue WAIT_REG_MEM consumers.

The accumulated source already has a packet-position path using
SubmitOrderedGuestActionWithVisibility. V2.17 extends that existing path only to:
- WRITE_DATA;
- producer length 1..16 bytes;
- no GPU readback requirement;
- no deferred label completion.

It does NOT:
- synthesize a label value;
- skip WAIT_REG_MEM comparison;
- change RELEASE_MEM/EOP;
- change the 24-submission hard cap;
- bypass the existing ordered guest queue.

Telemetry:
  [V74.0.67.2.17][SMALL_WRITE_PACKET_POSITION]

Slow-wait telemetry now additionally reports:
  producer_complete_ms=
  post_complete_wait_ms=

This separates producer queue latency from post-completion drain latency.

DLSS
====
DLSS code/provider is unchanged. Normal frontend activation remains:
  Rendering -> Upscaler Enabled -> DLSS -> preset -> Execute.

RUN_5 deliberately does not force SHARPEMU_VK_UPSCALER from PowerShell.
