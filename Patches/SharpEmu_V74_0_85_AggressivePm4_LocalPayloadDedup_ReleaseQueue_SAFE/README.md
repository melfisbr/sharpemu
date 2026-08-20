# SharpEmu V74.0.85 — Aggressive PM4 / Local Payload Dedup / Release Queue

Targets the post-V84 bottlenecks proven by the Demon’s Souls runtime: nearly one Vulkan submit per work item, repeated 320 MB texture-array payloads, high private memory, and conservative ordered memory side effects.

Changes:
1. Enables the existing Kyty PM4 blocked-queue scheduler by default (`SHARPEMU_KYTY_PM4_BLOCKED_SCHEDULER=0` restores legacy).
2. Enables existing Kyty inline CPU-resident WRITE_DATA by default (`SHARPEMU_KYTY_INLINE_WRITE_DATA=0` restores legacy).
3. Deduplicates >=1 MiB non-storage texture payloads inside one draw/dispatch before they enter the renderer queue. The first binding keeps the payload; later identical-content bindings keep descriptor/sampler identity but carry no second byte payload (`SHARPEMU_LOCAL_TEXTURE_PAYLOAD_DEDUP=0` disables).
4. RELEASE_MEM remains ordered after real queue completion but uses queue-completion-only instead of global dirty-buffer readback (`SHARPEMU_RELEASE_MEM_QUEUE_COMPLETION_ONLY=0` restores conservative GPU->CPU visibility).
5. Preserves V81.2 Vulkan boundaries, V82 nonblocking visibility/DCC index and V84 adaptive unified compute.

This is intentionally more aggressive. If rendering correctness regresses, set the four environment switches to `0` individually to isolate the unsafe optimization before rolling back the package.
