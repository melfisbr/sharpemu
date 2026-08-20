# SharpEmu V74.0.88 — Deferred Tiled Direct Staging / Gate Escape

Aggressive performance correction based on V87.2 runtime evidence. V87.2 successfully yielded the Gate 8192 times but could only yield after an individual packet finished. A 320 MiB tiled-array snapshot was followed by an ~861 ms packet interval and ~888 ms Gate wait.

V88 changes the transport contract for supported Vulkan GPU-detile textures >= 8 MiB:

1. AGC records a lazy guest-memory tiled reference (address, stride, base offset, slice bytes) instead of allocating/filling a large managed `byte[]` under `gpuState.Gate`.
2. `VulkanDetilePass` maps its host-visible staging buffer and reads guest slices directly into that mapped memory on the render thread.
3. This removes one full host copy and the huge managed allocation from the parser hot path.
4. If direct staging cannot read the guest backing, V88 materializes the old tiled snapshot on the render thread and keeps the old GPU/CPU fallback semantics.
5. `SHARPEMU_DEFER_LARGE_TILED_GUEST_READ=0` restores the legacy parser-copy path. `SHARPEMU_DEFER_LARGE_TILED_THRESHOLD_MB` overrides the default 8 MiB threshold.

V81.2 Vulkan correctness boundaries, V82 visibility, V84 compute/headroom, V85 PM4 semantics, V86.4 retention and V87.2 Gate quantum remain intact.

RUN_1 performs manifest/hash verification, Windows PowerShell parser validation, patch-data fixture tests, a read-only transform of all four current checkout files, transform idempotence, cumulative marker checks and lexical C# brace validation before RUN_3 is allowed to write.
