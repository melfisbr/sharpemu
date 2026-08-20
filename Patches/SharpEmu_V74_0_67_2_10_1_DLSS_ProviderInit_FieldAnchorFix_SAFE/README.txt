SharpEmu V74.0.67.2.10.1
DLSS ProviderInit FieldAnchorFix SAFE

The V2.10 NVIDIA NGX provider build PASSED. The managed patch then stopped at:
  Anchor 'provider init failure fields' count=0 expected=1

Cause:
V2.10 expected _upscalerInitHeight to be immediately followed by
MaxNativeUpscalerExtensions. V74.0.67 had already inserted runtime telemetry
counters between them. The accumulated source is valid; the V2.10 anchor was
stale.

V2.10.1 inserts the new failure-state fields after the unique
_upscalerInitHeight field and no longer depends on adjacency to
MaxNativeUpscalerExtensions.

Before source mutation, precheck validates the remaining downstream V2.10
anchors and the bounded TryInitializeUpscaler region.

RUN_3 reuses the already-built V2.10 provider when it exists and exports:
  sharpemu_vk_upscaler_get_last_error
Otherwise it rebuilds the provider.

No Vulkan/NGX design change was made. No guest resource address is hardcoded.

Runtime success remains:
  selected=dlss
  state=active
  dlss_dispatches>0

If provider initialization still fails, the expected telemetry is now:
  [V74.0.67.2.10][UPSCALER][PROVIDER_INIT] state=failed result=... last_error=...
