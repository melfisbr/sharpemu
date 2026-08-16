SharpEmu Demon's Souls Render / Scanout / Bink Handoff Audit V73.6 SAFE

V73.5 PROVED
- all five watched WRITE_DATA packets were applied;
- each watched label became visible=1 and latched=1;
- 14 waits resumed in the representative run;
- ordered fence sampled maximum fell to 64 (V73.3 was 128; earlier baseline >=512);
- runtime unresolved imports = 0;
- deviceLost = 0.

CURRENT BLOCKER SURFACE
The same run had zero:
  Vulkan VideoOut presented guest frame
and sampled known render-target addresses with gpu_resident=False.

It also selected an auto Bink sequence with 3 movies, but logged:
  bink2.direct_boot_completed frames=461
while still in logo_intro.bk2. V73.6 treats this as evidence to correlate, not
as proof of a Bink bug.

FOCUSED BUILT-IN TRACES
V73.6 enables only:
  SHARPEMU_TRACE_SCANOUT_LINEAGE=1
  SHARPEMU_RENDER_CHECKPOINTS=1
  SHARPEMU_TRACE_DCC_ALIAS=1

It explicitly sets:
  SHARPEMU_SCANOUT_RECOVERY=off

and disables full AGC/Vulkan/draw/frame/label-provenance tracing.

No repository source is modified.

CLASSIFICATION
The result classifies the next branch:
- post-bink-no-agc-flip-packets
- flip-packets-display-buffer-unresolved
- flip-lineage-present-but-no-guest-frame
- guest-frame-presentation-reached

The result also copies the exact current:
- AgcExports.cs
- VideoOutExports.cs
- VulkanVideoPresenter.cs
- HostMovieBridge.cs
- BinkRuntimeBootstrapV6113166.cs
- BinkHostPlaybackAssist.cs
- DirectExecutionBackend.cs
- DirectExecutionBackend.GuestSampler.cs

so the next package can patch the actual failing stage without another generic
source collector.

V73.5 AgcExports SHA-256:
  C1B8EBCE72344F2CB1E9E965CDDC947A982DFFC81425898222835C2C943C1CBF
V73.5 VulkanVideoPresenter SHA-256:
  049A1BBC5924DFD3A97AB94B3DBFAB1BE514D37FF03F0CE9748A8468B71FCC7C
