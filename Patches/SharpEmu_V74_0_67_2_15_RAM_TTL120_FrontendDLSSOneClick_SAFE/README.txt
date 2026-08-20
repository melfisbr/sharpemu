SharpEmu V74.0.67.2.15
RAM TTL120 + Frontend DLSS One-Click SAFE

LATEST RUNTIME
==============
DLSS is proven working:
  evaluate_dlss success=1
  selected=dlss
  state=active
  provider=1
  caps=0x9
  dlss_dispatches>0
  dispatch_failures=0

The process also ended with code 0.

The remaining memory issue is real:
  320 MiB large-array snapshots remain in the V74.0.64 multicache,
  alloc2s_mb still reaches roughly 1.6-2.0 GiB in several samples,
  and the runtime still reports ttl_ms=30000.

RAM ROOT CAUSE
==============
The existing environment knob is present, but the accumulated V74.0.64 TTL
value is capped at 30 seconds before cache lookup/telemetry consume it.

V2.15 does not replace the V74.0.64 cache and does not increase its entry
count. Instead it:
- preserves the existing V74.0.64 field;
- dynamically detects whether the field is int or long;
- redirects all later TTL consumers through an effective-TTL property;
- re-reads SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS with bounds 1000..120000;
- preserves the V2.13 content-identity key;
- preserves cache entries=2.

FRONTEND DLSS
=============
The normal Rendering UI already owns:
  UpscalerEnabled
  UpscalerBackend
  UpscalerQuality
  SHARPEMU_VK_UPSCALER
  SHARPEMU_VK_UPSCALER_QUALITY

The Vulkan backend already:
- defaults SHARPEMU_VK_UPSCALER_PRECOMPOSITE to true;
- auto-discovers:
    <SharpEmu.exe dir>\upscalers\SharpEmu.VulkanUpscaler.Native.dll
- uses nvngx_dlss.dll from the SharpEmu executable directory;
- uses a temporary NGX data directory if SHARPEMU_DLSS_DATA_PATH is unset.

V2.15 makes the GUI launch contract explicit:
- pre-composite = 1 when the Rendering upscaler toggle is enabled;
- RAM cache entries = 2;
- RAM snapshot TTL = 120000;
- detile idle pool = 64 MiB.

Therefore after V2.15 normal use is:
  Rendering -> enable Upscaler -> Backend DLSS -> choose Quality -> launch.

No RUN_5, PowerShell environment variable or manual provider path is required
for normal frontend activation, provided the V2.14/V2.15 Release host is used
and the already-deployed provider/nvngx DLLs remain beside that host.

RUN_5 intentionally clears forced validation-shell variables before opening
the GUI. This proves the frontend path itself.

DLSS truth remains:
  selected=dlss
  state=active
  dlss_dispatches>0

RAM proof:
  ARRAY_CACHE_OWNER / ARRAY_SINGLEFLIGHT ttl_ms=120000
  and lower alloc2s_mb / fewer large-array rematerializations.
