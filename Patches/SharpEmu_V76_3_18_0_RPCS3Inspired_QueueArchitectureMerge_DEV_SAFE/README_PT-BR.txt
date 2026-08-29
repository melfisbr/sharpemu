SharpEmu V76.3.18.0
RPCS3-inspired Queue Architecture Merge — DEV SAFE

Presenter baseline SHA256:
f7a98ce40383bbff5e5e030fff119476dbcfb0c27006cf417a5e3f0cf886746b

Presenter result SHA256:
712199a608bac7782f24fd35a52cce9071383638de61e0135d67d08bf85d92a6

Changed source:
- VulkanVideoPresenter.cs
- DemonsSoulsGpuQueueEnvelopeV74011224.cs (adaptive transform)

AgcExports.cs is NOT replaced. V17.0.1 async AGC is required and preserved.

Main merge:
- capability-driven real dual physical Vulkan queue
- DCB graphics queue0 / ACB compute queue1
- timeline + existing byte-range resource hazards
- automatic single-queue fallback
- guest command-buffer recycle pool 32 -> 256
- final authoritative title profile preserving V15-V17 fixes

Emergency A/B:
Set SHARPEMU_V763180_FORCE_SINGLE=1 before launching to force the old
single-queue path while keeping all other V18 merge settings.

Development build:
Debug / win-x64.

RUN_3 backs up Presenter + Agc + CLI before changing source and restores all
three automatically if restore/build fails.
