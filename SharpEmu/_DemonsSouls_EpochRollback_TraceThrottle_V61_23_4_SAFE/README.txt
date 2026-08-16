SharpEmu V61.23.4 SAFE

Self-healing correction for the post-video regression:
1. Detects the exact V61.23.1 eager label-history deletion block.
2. Removes that exact block rather than relying on brace-count heuristics.
3. Preserves real WRITE_DATA/DMA/RELEASE_MEM producer tracking.
4. Builds SharpEmu.Libs and SharpEmu.CLI; restores source automatically on build failure.
5. Runs Demon's Souls with all high-frequency AGC/Shader/Vulkan tracing disabled.
6. Collects low-frequency process telemetry to measure real runtime progress.

No WAIT_REG_MEM is force-satisfied.
