SharpEmu V76.3.20.4 — Watched WRITE_DATA Producer Fast Path DEV SAFE

Requires V20.3.

Enables existing narrow mechanisms that were already implemented in AgcExports:
- SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION=1
- SHARPEMU_CROSS_QUEUE_WATCHED_INLINE_WRITE=1
- SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY=1
- SHARPEMU_UPSTREAM003_DIRECT_DRAIN=1

The source itself restricts the inline path to immediate CPU-resident WRITE_DATA
whose exact address range is currently awaited by another logical guest queue.
Same-queue FIFO is preserved. RELEASE_MEM, DMA and GPU-buffer readback paths are
not promoted.

This specifically targets the current SLOW_WAIT_PRODUCER profile where the
producer is normally dcb.graphics WRITE_DATA and producer_complete_ms dominates.

V20.3 balanced queue pressure remains authoritative.
Build: Debug/win-x64.
