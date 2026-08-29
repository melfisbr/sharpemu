SharpEmu V76.3.18.1 — FAST GPU Resident Pipeline / Queue Merge

This package preserves V18.0 and adds one final authoritative FAST/Safe policy.
It does not replace VulkanVideoPresenter.cs or AgcExports.cs.

FAST profile (default):
- real dual physical Vulkan queue remains requested/capability-driven
- Async AGC command processor remains enabled
- Compute Chain4 remains enabled
- guest-work drain 1024 -> 4096 per Render()
- follow-up wait 2ms -> 0ms
- follow-up budget 24ms -> 48ms
- submission capacity wait 100ms -> 2ms
- persistent Vulkan pipeline cache enabled
- graphics pipeline cache 512 -> 1024
- compute pipeline cache 256 -> 1024
- descriptor-set cache max 512 -> 2048
- device buffer cache 512MB -> 1024MB
- writable guest buffer cache 256MB -> 512MB
- sampled guest-image cache 512MB -> 1024MB
- standalone texture cache 3072MB -> 4096MB
- DEVICE_LOCAL immutable globals enabled
- ReBAR direct globals enabled
- runtime scalar direct enabled
- producer slices, exact hazards, waits, EOP, WRITE_DATA preserved
- failed host-only sideband remains OFF

SAFE A/B:
Set SHARPEMU_V763181_SAFE=1 before launching. This restores the conservative
cache/feed limits while leaving V18 dual queue, V17 Async AGC and all correctness
fixes in place.

Why:
The current source already contains resident shader modules, fast compute/graphics
pipeline identity caches, descriptor-set reuse, device-local immutable globals,
ReBAR direct buffers, resource-range hazards and timeline sync. This merge raises
the working-set and feed limits so the RTX can retain more prepared state and the
dedicated render thread can feed the physical queues more aggressively.

Debug / win-x64. RUN_3 creates backup and automatically rolls back on build failure.
