SharpEmu V76.3.21.1
MAX Critical Path Consolidated Merge — DEV SAFE

This package is based on the effective V21.0 source state already present in
the current checkout.

Changed source:
- SharpEmu.Libs\Agc\AgcExports.cs
- SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs

VulkanVideoPresenter.cs is NOT replaced. The package validates that all required
V21 scheduling capabilities already exist and configures them through the final
title profile.

Highlights:
- planned producer query 64 -> configurable 256/1024
- producer closure activation 50ms
- FIFO producer scan 4096
- 16x128 producer slices, 250us fairness
- compute chain 8
- draw command buffer 32
- ordered microbatch 64
- real dual queue retained
- Async AGC retained
- balanced 192/96 burst4 inflight16 retained
- V21 cache/residency capacities retained
- sideband OFF
- control-lane bypass OFF
- waits/hazards/fences unchanged

RUN_3 builds Debug / win-x64.
On any apply/restore/build failure, AgcExports.cs and CLI are restored
automatically from a PRE_SOURCE ZIP.

RUN_4 is intentionally longer: it gathers ~180 seconds after main loop when
possible and samples NVIDIA utilization every 5 seconds when nvidia-smi exists.
