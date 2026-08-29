SharpEmu V76.3.19.0 — TURNO 1
Shader Frontend Hotset / Set-Associative L2 / Residency Merge — DEV SAFE

BASE
Requires V76.3.18.0 queue merge + V17.0.1 async AGC + V17.1 Chain4.

WHY
At 32768 frontend evaluations the previous run still had:
- program shared lookups = 2409
- metadata shared lookups = 3245
- scalar scratch clones = 35571 (pool-backed, zero fallbacks)
- global reads = 32771
- snapshot misses = 73219

The program/metadata cache is exact but direct-mapped. V19.0 converts only this
thread-local lookup layer to 4-way set associative; the shared cache remains the
authoritative fallback.

It also makes the already-validated immutable global residency hotset admit
reused ranges earlier. Write generation checks remain unchanged, and any write
continues to disable that resident base.

V19.0 SETTINGS
- shader thread L2: 4096 sets x 4 ways = 16384 exact-key entries/thread
- shared decoded program cache: 8192
- shared metadata cache: 8192
- resident shader max: 2048
- descriptor set cache: 4096
- read-only global residency: 640 entries / 384 MiB
- generic admission observations: 3
- medium >=256KiB observations: 2
- large >=1MiB observations: 2
- deferred global reads: ON
- ReBAR global direct: ON
- Vulkan host-buffer cache: 192 MiB

UNCHANGED
- V18 physical queue architecture/timelines
- V17.0.1 async AGC
- V17.1 Chain4
- waits / WRITE_DATA / RELEASE_MEM / hazards
- compute barriers
- Bink
- safe memcpy
- host sideband OFF / ordered microbatch ON

This turn targets frontend CPU work only. It deliberately does not change shader
semantics or queue synchronization.

Known local translator baseline used for structural validation:
6ab9a170fde5f6fc587f427bd0538e0a65a21ac93d3ef7f804cfd0cedc492a6b

Local transformed reference hash:
3a60ee35469bf0026e7760f66b3408ea9cc9d4735df8a711cb7098b87bf2eaf0

The runtime package applies by exact anchors and prints the actual SHA on the
user checkout after build.
