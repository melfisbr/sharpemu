SharpEmu V74.0.67.2.13
DLSS Activation + RAM Pressure Fix SAFE

Latest runtime:
- DLSS requested but selected=off/provider=0/dlss_dispatches=0.
- Scene input was already valid at 2560x1440 -> 3840x2160 with color/depth/motion.
- Managed heap reached >8 GiB and private bytes ~18.6 GiB.
- Two recurring array payloads were 335,544,320 bytes each and reused with a short TTL.

DLSS corrections:
- explicit NVSDK_NGX_FeatureCommonInfo feature path = SharpEmu.exe directory;
- explicit nvngx_dlss.dll presence check;
- NGX app logging callback;
- failed provider initialization no longer unloads the provider;
- same-size failed init retries on a bounded ~2 second timer;
- size changes retry immediately;
- exact LastError is emitted on every bounded failure;
- RUN_5 forces DLSS + Quality + pre-composite and explicit provider path.

RAM corrections:
- large-array single-flight identity uses a 32x64-byte distributed content probe
  when guest write tracking is unavailable;
- exact WriteGeneration identity is preserved when tracking is enabled;
- failed probes never reuse stale snapshots;
- large-array reuse has a 60-second minimum;
- RUN_5 requests cache=2 and reuse=120 seconds;
- validation run reduces Vulkan detile idle pool to 64 MiB.

BPE V2.11/V2.12 menu-crash fixes are preserved.

DLSS is only proven working by:
  selected=dlss
  state=active
  dlss_dispatches>0

RUN_3 backs up VulkanUpscalerBridge.cs, AgcExports.cs and
DirectExecutionBackend.Exceptions.cs and restores them on build failure.
