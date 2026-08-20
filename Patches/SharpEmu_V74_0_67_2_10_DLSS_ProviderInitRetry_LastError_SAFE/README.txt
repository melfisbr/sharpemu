SharpEmu V74.0.67.2.10
DLSS Provider Init Retry + LastError SAFE

LATEST RUNTIME
==============
V74.0.67.2.9 succeeded: raw_candidates=5 collapsed to distinct_sources=1 and the 2560x1440 scene source is selected with valid depth and R16G16Sfloat motion.

The next gate fails before dispatch:
  requested=dlss
  selected=off
  provider=0
  caps=0x0
  color=1 depth=1 motion=1
  input=2560x1440 output=3840x2160
  dlss_dispatches=0
  reason=precomposite_provider_init_failed

V2.10 fixes/instruments that exact gate.

1. Rebuilds and redeploys the consolidated V2.8 NVIDIA NGX Vulkan provider and nvngx_dlss.dll.
2. Managed bridge loads optional sharpemu_vk_upscaler_get_last_error.
3. Captures the native initialize return code and NGX error text before unloading a failed provider.
4. Fixes failed-init output-size poisoning: a failure at one output size may retry when the requested target changes, but never loops every frame for the same size.
5. Adds PROVIDER_LOAD / PROVIDER_INIT telemetry.
6. Preserves V2.9 source identity, V2.5 depth, V2.6 motion, V2.8 extension negotiation and V74.0.73 hot path.

No runtime guest address is hardcoded.
DLSS is active only when selected=dlss state=active dlss_dispatches>0.
