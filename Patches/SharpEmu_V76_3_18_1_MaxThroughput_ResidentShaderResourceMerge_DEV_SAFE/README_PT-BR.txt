SharpEmu V76.3.18.1
MAX THROUGHPUT / RESIDENT SHADER+RESOURCE MERGE — DEV SAFE

REQUIRES
V76.3.18.0 Presenter SHA256:
712199a608bac7782f24fd35a52cce9071383638de61e0135d67d08bf85d92a6

THIS PACKAGE DOES NOT REPLACE Presenter OR AgcExports.
It only appends one authoritative Demon's Souls title profile, preserving all
code and merges already validated.

PRESERVED
- V18 capability-driven dual physical Vulkan queues
- V17.0.1 Async AGC command processor
- V17.1 Compute Chain 4
- V16.1.1 producer slices
- V15.1 safe memcpy
- WAIT/WRITE_DATA/RELEASE_MEM/EOP/hazards/timelines
- host-only sideband OFF
- ordered microbatch ON
- command-buffer recycle pool 256

MAX MODE ADDS/CONSOLIDATES
- DrawCommandBuffer max 16
- preserve payload batch
- compute resource setup coalesce
- resident shaders max 8192
- graphics pipeline cache 1024
- compute pipeline cache 512
- descriptor set cache 1024
- DEVICE_LOCAL immutable globals
- ReBAR direct globals
- direct runtime scalar path up to 16 KiB
- selective persistent global residency:
    256 entries
    128 MiB
    64 KiB floor
    hot/reuse admission
- larger bounded resource reuse caches:
    host staging 128 MiB
    sampled images 1024 MiB
    standalone textures 4096 MiB
    writable guest buffers 512 MiB
    device buffers 1024 MiB
- nonblocking global refresh
- producer-less wait fallback 32 ms
- capacity fence probe 50 us
- expensive hotpath traces/censuses disabled
- pipeline cache periodic save 600 s

SAFE FALLBACK
Before launching SharpEmu:
    $env:SHARPEMU_V763181_SAFE_MODE = "1"

Safe mode keeps V18 architecture but returns the aggressive V18.1 items to:
- draw max 8
- shader globals residency OFF
- resident shader max 4096
- descriptor cache 512
- graphics/compute pipeline cache 512/256
- original resource cache budgets
- blocking global refresh behavior
- wait fallback 16 ms
- capacity probe 100 us

To return to MAX:
    Remove-Item Env:SHARPEMU_V763181_SAFE_MODE -ErrorAction SilentlyContinue

WHY
This targets the CPU work before VkQueueSubmit: repeated resource/global/pipeline
preparation. It does not fake VRAM usage and does not remove guest synchronization.
Cache budgets are maximum retained working sets, not preallocations.
