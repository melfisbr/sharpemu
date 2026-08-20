SharpEmu V74.0.67.2.13.2
DLSS + RAM Diagnostic Telemetry Owner Fix SAFE

STATUS OF V2.13.1
=================
V2.13.1 successfully:
- built the native NVIDIA NGX Vulkan provider;
- applied the V2.13 bounded provider activation retry;
- applied the V2.13 large-array content-identity RAM patch;
- built SharpEmu Release successfully;
- deployed SharpEmu.VulkanUpscaler.Native.dll;
- deployed nvngx_dlss.dll.

RUN_4 then failed on only:
  active_telemetry=false

All other DLSS/RAM/BPE/provider checks were true.

ROOT CAUSE
==========
The provider-init active telemetry is source owned by V74.0.67.2.13:

  [V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active

V2.13.1 fixed the RAM multicache precheck but did not retag that already
implemented runtime feature.

Its diagnostic incorrectly searched for the package tag V2.13.1.

V2.13.2
=======
Corrects only the diagnostic ownership check.

No Vulkan, NGX, RAM, BPE or emulator runtime source changes are made.
RUN_3 is intentionally a structural/binary deployment check and does not
rebuild the emulator.

EXPECTED RUN_4
==============
  dlss_retry_marker=true
  provider_is_initialized=true
  retry_timer=true
  provider_retained=true
  active_telemetry=true
  active_telemetry_owner_v213=true
  ram_marker=true
  ram_content_key=true
  ram_sparse_probe=true
  ram_v74064_ttl_field=true
  ram_v74064_ttl_env=true
  bpe_v212=true
  deployed_provider_exists=true
  deployed_nvngx_exists=true
  export_sharpemu_vk_upscaler_get_last_error=true
  DIAGNOSTIC PASSED.

IMPORTANT
=========
This structural pass still does not prove DLSS executed at runtime.

Runtime DLSS proof remains:
  selected=dlss
  state=active
  dlss_dispatches>0

RAM runtime proof:
  ARRAY_CACHE_OWNER / ARRAY_SINGLEFLIGHT ttl_ms=120000
  and materially reduced alloc2s_mb / heap_mb / private_mb versus baseline.
