SharpEmu V74.0.15 SAFE - Demon's Souls large-array single-flight

Purpose
-------
V74.0.14 removed the previous device-loss regression and reached the game main loop in
~31.7 seconds, but a valid 320 MB texture array coincided with a 5.3 GB/2 s managed
allocation burst and a black screen. V74.0.15 coalesces concurrent copies of exact
>=64 MB array payloads for 500 ms, in both GPU-tiled and CPU-linear array upload paths.

Correctness constraints
-----------------------
- no array layers are skipped
- no fake/fallback texture is substituted for the array
- cache key includes descriptor identity, layers, generation and tiled/linear path
- only one retained large-array snapshot exists at a time
- V74.0.5 non-array cache is bounded to <=32 MB
- 768 MB Vulkan texture cache is preserved to avoid the V74.0.13.2 trim/device-loss path
- NativeWorker is not overwritten or modified by this package

Test profile
------------
render_scale=0.25 (test only)
GPU detile explicitly enabled
TBB/native worker=2
renderer/resource lane=8
standalone texture cache=768 MB
sampled guest image cache=256 MB
guest buffer cache=192 MB
device buffer cache=384 MB
Bink auto-boot remains disabled; natural guest movie requests are observed.

Execution
---------
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_ARRAY_SINGLEFLIGHT.cmd

The runner records process-tree and runtime memory, max alloc2s_mb, array single-flight
owner/reuse hits, Vulkan device loss/heap corruption, movie milestones, and a result ZIP.
