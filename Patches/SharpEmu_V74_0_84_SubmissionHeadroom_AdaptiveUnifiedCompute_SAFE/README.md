# SharpEmu V74.0.84 — Submission Headroom + Adaptive Unified Compute

V82.1 removed blocking ordered-fence waits but runtime remained near 2.2 FPS. The log repeatedly hits `pending_gpu=8 cap=8`, while the source already contains two bounded optimizations that remained opt-in:

1. V74.0.33/V74.0.43 submission fairness/headroom. Soft target stays 8, existing emergency hard ceiling stays 24, FIFO/RequiredSequence and physical Vulkan submission order stay intact. `SHARPEMU_KYTY_COMPUTE_SUBMISSION_FAIRNESS=0` restores legacy.
2. V74.0.56.16 adaptive unified compute. Only direct non-indirect dispatches with total workgroups within the existing 65,536 default budget are unified; no workgroups are skipped. `SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE=0` restores legacy.

V81.2 Vulkan boundaries, V82 nonblocking visibility and DCC metadata index are preserved. RELEASE_MEM/readback semantics are deliberately not changed in this package.
