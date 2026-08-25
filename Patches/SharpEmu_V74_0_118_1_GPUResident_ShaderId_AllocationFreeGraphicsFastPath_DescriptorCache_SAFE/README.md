# SharpEmu V74.0.118.1 — GPU-Resident ShaderId + Allocation-Free Graphics Fast Path SAFE

Apply directly to the restored V117.14 baseline. Do NOT apply V117.16 or V118.0.1 first.

Cumulative contents:
- V117.16 fence-safe descriptor-set block cache;
- V118.0.1 Windows PowerShell 5.1-safe GPU-resident ShaderId / resident VkShaderModule logic;
- V118.1 shader-reference zero-scan hot path;
- V118.1 allocation-free graphics pipeline fast lookup.

V118.0 still built render-target, blend and vertex-layout strings before its graphics "fast"
lookup. V118.1 moves the lookup before those string builders.

The V118.1 variable-state key uses a 64-bit signature only to locate a bucket. It never trusts
that hash as pipeline identity: render-target formats, every GuestBlendState and every vertex
layout element are exact-compared field-by-field before a VkPipeline is returned. A collision
therefore causes an extra comparison, not wrong pipeline reuse.

The existing SharpEmu `_shaderDigests` cache already treats a translated `byte[]` SPIR-V object
as immutable. V118.1 uses that same existing contract:
- same byte[] reference: zero full-SPIR-V rescan;
- different byte[] reference: exact SequenceEqual is still mandatory;
- a different reference is promoted to the hot reference only after exact equality.

DeviceLost safety:
- no VkImage/VkImageView reuse;
- no texture ownership change;
- no guest-buffer-content change;
- no queue widening/reordering;
- no WAIT_REG_MEM/WRITE_DATA bypass;
- no barrier change;
- no Pair2 change;
- no dual physical VkQueue;
- no vkQueueSubmit change.

Resident pipeline entries reference only pipelines owned by the canonical existing pipeline caches.
Resident VkShaderModules remain immutable and are destroyed only after DeviceWaitIdle at shutdown.
