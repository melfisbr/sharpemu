# SharpEmu Demon's Souls — Full Runtime Truth Audit V74.0.8.1 SAFE

This supersedes V74.0.8. It installs the same standalone texture-cache byte
budget, but the diagnostic is no longer a one-parameter experiment.

One 120-second run measures all remaining decision variables simultaneously.

## Internal 2-second telemetry

`[V74.0.8.1][MEM]` reports:

- GC live bytes, heap size and fragmentation;
- GC memory load / high-memory threshold / available memory;
- Gen0 / Gen1 / Gen2 collection counts;
- allocation delta per 2 seconds;
- working/private/virtual/paged memory;
- handles and thread count;
- standalone Vulkan texture cache bytes and deferred bytes;
- texture entry and deferred-destroy counts;
- sampled GuestImage bytes, image/variant/version counts;
- guest-buffer cache bytes/count;
- pending GuestImage CPU data bytes and upload count;
- frame staging buffers waiting on fence;
- graphics/compute pipeline counts;
- pending/abandoned submissions, batch-resource count and timeline.

## OS telemetry sampled every second

- process-tree working/private/virtual/paged/handles/threads/CPU/I/O;
- Windows system available memory, commit, commit limit and kernel pools;
- Windows per-process GPU dedicated/shared/committed memory and utilization;
- NVIDIA utilization/VRAM/temperature/power when nvidia-smi is available.

## Runtime traces enabled together

- direct-memory allocations;
- VM mappings;
- lazy commit;
- GPU wait aggregate profile;
- VideoOut FPS;
- guest-thread state snapshots;
- texture/DCC/compute/Bink/UI evidence already present in the accumulated code.

Very high-volume per-resource/per-instruction Vulkan and AGC traces stay OFF.
They perturb the measured workload and are no longer necessary because the
aggregate counters cover the same decision boundary.

Baseline presenter:
`1D8EE63DCB2F4E2A1EEC595535F40224FBE06E1DD16531233597F24740A02A28`

V74.0.8.1 presenter:
`0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66`
