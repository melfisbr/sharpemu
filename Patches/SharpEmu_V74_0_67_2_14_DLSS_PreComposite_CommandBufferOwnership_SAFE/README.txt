SharpEmu V74.0.67.2.14
DLSS Pre-Composite Command Buffer Ownership SAFE

The latest runtime proves NVIDIA NGX initialization succeeded:
  init_project_id success=1
  get_capability_parameters success=1
  initialize success=1
  PROVIDER_INIT state=active result=0 caps=0x9

Immediately afterward SharpEmu crashed with 0xC0000005 inside
Silk.NET.Vulkan.Vk.CmdPipelineBarrier called by
TryPrepareUpscalerPreCompositeForConsumer.

Root cause:
TryPrepare is intentionally invoked before CreateTranslatedDrawResources so
the DLSS output can replace the source texture during descriptor translation.
The normal ExecuteOffscreenDrawCore assignment of the shared batch command
buffer occurs only after CreateTranslatedDrawResources. Therefore the
pre-composite method could issue RecordGuestImageForSampling/barrier/NGX
commands while _commandBuffer still referenced a presentation or non-recording
command buffer.

V2.14 acquires/reuses BeginBatchedGuestCommands and explicitly assigns
_commandBuffer before the first command-recording operation, then closes any
open translated render pass before compute/barrier recording.

Expected runtime:
  [V74.0.67.2.14][UPSCALER][COMMAND_BUFFER] state=recording ...
  create_dlss_feature ...
  evaluate_dlss ...

DLSS is only proven fully active by:
  selected=dlss
  state=active
  dlss_dispatches>0

RAM:
the last run reported ttl_ms=30000. RUN_5 now sets both
SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS and
SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS to 120000 so the accumulated cache
owner cannot select the adjacent 30-second value during this validation run.

RUN_1 performs SHA256, PowerShell parsing, StrictMode, runner mapping and patch
structure checks. RUN_2 validates the real checkout and simulates the required
command-buffer insertion in memory before RUN_3 is allowed to modify source.
RUN_3 backs up VulkanUpscalerBridge.cs and restores it automatically on build
failure.

Native NGX provider, RAM source logic and BPE source logic are preserved.
