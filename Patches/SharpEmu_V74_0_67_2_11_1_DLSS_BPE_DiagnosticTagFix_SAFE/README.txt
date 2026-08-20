SharpEmu V74.0.67.2.11.1
DLSS + BPE Diagnostic Tag Fix SAFE

STATUS OF V74.0.67.2.11
=======================
RUN_3 completed successfully:
- BPE end-sentinel return repair applied;
- SharpEmu Release build completed with 0 errors;
- native provider redeployed;
- nvngx_dlss.dll redeployed.

RUN_4 failed on only:
  provider_init_telemetry=false

Every related structural/binary check was true, including:
- lazy LastError support;
- initialize result capture;
- size-change retry state;
- BPE RAX=payload repair;
- V2.9 source selection;
- V2.5 depth / V2.6 motion;
- Vulkan instance/device hooks;
- deployed native provider and nvngx_dlss.dll;
- all native provider exports including get_last_error.

ROOT CAUSE
==========
Provider-init telemetry was implemented by V74.0.67.2.10.2 and intentionally
retains this source/runtime tag:

  [V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT]

V2.11 added the BPE repair but did not retag older accumulated features.

Its diagnostic accidentally searched for:
  [V74.0.67.2.11][UPSCALER][PROVIDER_INIT]

This caused a false STRUCTURAL/BINARY DIAGNOSTIC FAILED.

V74.0.67.2.11.1
================
Only corrects that diagnostic ownership expectation.

No runtime code or emulation behavior is changed:
- BPE V2.11 repair is preserved;
- DLSS V2.10.2 lazy LastError/retry logic is preserved;
- native NGX provider is unchanged.

EXPECTED RUN_4
==============
  provider_init_telemetry=true
  provider_init_telemetry_owner_v2102=true
  bpe_end_sentinel_marker=true
  bpe_returns_payload=true
  export_sharpemu_vk_upscaler_get_last_error=true
  DIAGNOSTIC PASSED.

Runtime remains the real proof.

Crash fix:
  BPE_LOW_SENTINEL_RECOVERY ... -> rax=payload
  no follow-up AV target=0x20 at RIP 0x800880D6D.

DLSS:
  selected=dlss
  state=active
  dlss_dispatches>0

Or, on provider failure:
  [V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT]
  state=failed result=... last_error=...
