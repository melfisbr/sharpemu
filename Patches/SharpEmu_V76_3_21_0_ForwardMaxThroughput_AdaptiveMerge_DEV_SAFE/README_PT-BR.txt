SharpEmu V76.3.21.0
Forward Max Throughput Adaptive Merge — DEV SAFE

WHY THIS PACKAGE IS FORWARD-ONLY
================================
The rejected V18.1 package expected Presenter SHA:
712199a608bac7782f24fd35a52cce9071383638de61e0135d67d08bf85d92a6

The actual checkout reported:
25b4794b8e71a99d5c8997bcd0e01e1edb0e3210fa4ddf4659b3eae6b6b3ae2d

That newer source already contains V20.4/V20.5/V18.5-era work. V21.0 therefore
does NOT replace VulkanVideoPresenter.cs or AgcExports.cs with older snapshots.

It validates capabilities/markers and edits the installed files in place.

PRESERVED
=========
- V17.0.1 asynchronous AGC command processor
- V17.1 Chain4
- V18 real dual physical graphics/compute queues + timelines/range hazards
- V20.4 watched WRITE_DATA producer fastpath
- V20.5 1536-entry/512MB resident global hotset
- descriptor cache 4096
- resident shader 2048
- Async shader stage compilation + 512/128MB SPIR-V prewarm
- safe memcpy
- producer slices
- sideband OFF
- ordered microbatch ON
- WRITE_DATA / RELEASE_MEM / WAIT_REG_MEM semantics

NEW/CONSOLIDATED MAX PROFILE
============================
1. Final authoritative profile is appended after all historical bootstraps.
2. Host frames in flight:
      SAFE=2 / MAX=3
   Existing per-frame fences/timelines remain authoritative.
3. Reusable guest command buffers/fences are guaranteed >=256.
4. Draw command buffer:
      SAFE=8 / MAX=16
5. Adaptive unified compute remains ON.
6. Compute Z slice budget:
      SAFE=64 / MAX=128
7. V20.4 producer fastpath is made authoritative.
8. Producer-less full wait scan:
      SAFE=16ms / MAX=32ms
9. Nonblocking writable-global refresh is enabled; this uses the existing exact
   timeline deferral and never fabricates completion.
10. Device-local immutable globals + ReBAR/scalar direct paths remain enabled.
11. V20.5 global residency is kept at:
      MAX 1536 entries / 512MB
12. Descriptor cache:
      4096
13. Resident shader:
      2048
14. Graphics/compute pipeline caches:
      MAX 1024 / 512
15. Resource cache caps:
      host 256MB
      sampled images 1024MB
      standalone textures 4096MB
      guest buffers 512MB
      device buffers 1024MB
    These are ceilings, not eager VRAM allocations.
16. CPU policy remains compact 16 native / 8 renderer.
17. Hot-path census/debug logging is disabled.

SAFE FALLBACK
=============
Set before launch:
  $env:SHARPEMU_V763210_SAFE_MODE = "1"

SAFE keeps all correctness fixes, dual queue, Async AGC, watched producer,
residency and caches but uses:
- 2 frames in flight
- draw CB max 8
- compute Z 64
- wait fallback 16ms
- slightly smaller image/texture/guest-buffer caps.

BUILD
=====
Debug / win-x64.
Backup of Presenter + Agc + CLI occurs before modification.
Any transform/restore/build failure automatically restores all three files.
