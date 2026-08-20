SharpEmu V74.0.67.2.10.2
DLSS LazyLastError / Loader-Compatible Provider Init Retry SAFE

ROOT CAUSE OF V2.10.1 FAILURE
=============================
V2.10.1 fixed the _upscalerInitHeight field anchor, but then failed at:

  Anchor 'provider loader diagnostics' count=0 expected=1

The accumulated checkout already contains V74.0.67.1 provider bootstrap/load
diagnostics. V74.0.67.1 changed the TryLoad body, so the older V74.0.64 full
TryLoad block used by V2.10/V2.10.1 no longer exists verbatim.

This is another patch-mechanics conflict, not an NVIDIA NGX failure.

The V2.10 native provider itself already built successfully, and the diagnostic
proved:
  export_sharpemu_vk_upscaler_get_last_error=true

V2.10.2 STRATEGY
================
Do not rewrite NativeVulkanUpscaler.TryLoad at all.

V74.0.67.1 remains the owner of provider load diagnostics.

The managed bridge instead:
- adds the optional GetLastErrorDelegate type;
- keeps a nullable cached delegate;
- resolves sharpemu_vk_upscaler_get_last_error lazily from the existing
  NativeLibrary handle using NativeLibrary.TryGetExport;
- exposes LastError and HasLastErrorExport without changing the constructor or
  TryLoad call shape;
- records the native initialize integer result;
- latches a failed output size;
- retries initialization only when the requested output dimensions change;
- never retries every frame for the same failed dimensions;
- emits exact PROVIDER_INIT last_error telemetry.

PRECHECK
========
Every exact anchor used by patch_source is validated before modification,
including all four anchors inside the bounded TryInitializeUpscaler region.

No provider-loader-body anchor is required.

PROVIDER
========
RUN_3 reuses the successful V2.10 provider when available and valid. It rebuilds
only when the cache is absent/invalid.

DLSS TRUTH
==========
DLSS is active only with:
  selected=dlss
  state=active
  dlss_dispatches>0
