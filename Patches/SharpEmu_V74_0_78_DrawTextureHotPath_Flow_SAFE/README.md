# SharpEmu V74.0.78 — Draw Texture Hot Path Flow SAFE

Target: Demon’s Souls PPSA01341 draw/compute resource preparation stalls.

The runtime logs showed:
- DRAW/COMPUTE resource time dominated by texture_ms (150–320 ms samples).
- V74.0.73 sampler aliases only discovered after 16 MiB-class texture snapshots had already been produced.
- waiter/drain latency while producer_state was already completed, correlated with long AGC Gate ownership.

Changes:
1. Vulkan sampler-agnostic texture-content index.
   `IsTextureContentCached()` now recognizes an already-resident texture whose content identity is identical except for sampler state. The AGC can therefore send an empty payload before snapshot/detile, and the existing V74.0.73 presenter alias supplies the requested sampler.
2. Large single-texture snapshots use `GC.AllocateUninitializedArray<byte>` because the full buffer is overwritten by the guest read.
3. `SignalGpuWaitMonitor()` coalesces an immediate drain request when real GPU waiters exist and a drain context is available. It does not synthesize label values or producer completion.
4. The wait monitor publishes/clears its drain context, allowing producer writeback/visibility signals to wake the existing drain path without waiting for the next polling interval.

This package is structural and has no rigid source SHA gate. It preserves accumulated source changes and aborts before writing if required contracts are missing.

Execution order:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_TEST_DIAGNOSTIC.cmd
