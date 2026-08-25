# SharpEmu V74.0.119.0.2 — Execution Graph / ReBAR / Shader Single-Flight / Wait Fast Path — Baseline Fix

Required baseline: V118.0.1 successfully applied.

Why this is different:
V118.0.1 proved that shader/pipeline identity is already hot:
- 65,536 resident shader lookups
- 52,155 address hits
- 40,287 compute pipeline fast hits
- 12,471 graphics pipeline fast hits
- zero shader fallback
- still ~0.6 FPS

Therefore V119.0 does not add another independent pipeline cache. It treats the renderer as a
feed graph:

AGC PM4
  -> exact waiter dependency
  -> shader structural cache / single-flight miss
  -> immutable ShaderId
  -> resource preparation
  -> descriptor lease
  -> resident pipeline
  -> command record
  -> single Vulkan queue submission

Changes:
1. Wait monitor uses the already-existing exact producer latch before a full waiter scan.
2. Shader cache misses are single-flight per exact structural key.
3. Resident ShaderId first tests the exact immutable byte[] reference. Byte-by-byte validation
   remains for a new array at the same address.
4. ReBAR direct globals:
   if Vulkan exposes DEVICE_LOCAL|HOST_VISIBLE|HOST_COHERENT memory, deferred immutable global
   buffers are populated directly in shader-readable GPU-local mapped memory. No upload buffer,
   CmdCopyBuffer or transfer barrier is needed. Unsupported devices use the exact V117.12 path.
5. V117.13 shader-global residency is disabled because measured benefit was negligible relative
   to its tracking/cache cost. V117.12 single-copy live read remains.
6. Resident shader maximum is reduced from 4096 to 1024; measured working set was ~222.
7. RenderPhaseProfile is enabled at 5-second intervals so the next step is chosen from self-time,
   not another hypothesis.

Not changed:
- same-queue FIFO
- normal 18/96 queue envelope
- producer cap 48
- Pair2
- compute barriers
- vkQueueSubmit
- physical VkQueue count
- VkImage/VkImageView ownership
- texture lifetime
- WRITE_DATA semantics

## V119.0.1 ReBAR robustness

The execution-graph design is unchanged. The optional ReBAR branch now:
- caches an unsupported-memory-type result instead of probing every global binding;
- falls back to V117.12 on BAR allocation/bind/map failure;
- initializes all output handles explicitly (PowerShell/C# build-safe path);
- cleans mapped memory in Vulkan lifetime order if pool registration fails.

This prevents an unsupported or pressured BAR heap from becoming a new CPU hot loop or fatal path.


## V119.0.2 baseline-owner fix

V119.0.1 incorrectly looked for `HasLatchedSatisfiedV74100` inside `AgcExports.cs` during
PRECHECK. The API is actually defined in `GpuWaitRegistry.cs`; AGC only calls it.

V119.0.2 changes only the harness/baseline validation:
- AGC validates its own shader-cache / drain / monitor markers;
- GpuWaitRegistry validates `HasLatchedSatisfiedV74100` and the latched collector;
- the GpuWaitRegistry SHA is recorded at PRECHECK and rechecked before build;
- GpuWaitRegistry.cs remains read-only and is not patched;
- the V119.0.1 execution-graph/ReBAR C# patch is byte-for-byte unchanged.

The V119.0.1 failure occurred before APPLY, so no rollback is required.
