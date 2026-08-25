# V118.0.1 GPU-Resident ShaderId + Pipeline Fast Path — PS 5.1 Harness Fix

This package supersedes V117.16: apply it directly to the restored V117.14 baseline.

It includes the V117.16 fence-safe descriptor-set block cache, then adds a resident shader catalog.

Safety rules:
- exact SPIR-V SequenceEqual before address reuse;
- content change at same guest address creates a new ShaderId/version;
- resident VkShaderModule is immutable and kept until DeviceWaitIdle shutdown;
- canonical Vulkan pipeline cache remains authoritative;
- direct fast maps only reference pipelines already owned by canonical caches;
- max 4096 resident shader programs; overflow falls back to old path;
- no VkImage reuse, no texture ownership change, no buffer-content cache;
- no queue, barrier, Pair2, dual-queue or vkQueueSubmit changes.

This is phase 1 of a GPU-driven architecture. It does not make NVIDIA hardware interpret raw PS5 ISA.
It removes repeated host-side shader identification/module construction after the program is known.

## V118.0.1 correction

V118.0 failed in PRECHECK only. No repository source was modified.

Cause: the transform helper was named `R`. On Windows PowerShell 5.1, short command
names can collide with aliases during command resolution. The first source here-string
was therefore treated as a positional argument to the wrong command.

V118.0.1 changes no C# feature logic. It replaces the patch helpers with:
- `Replace-OnceV1180`
- `Normalize-NewlinesV1180`
- `Write-Utf8NoBomV1180`

The original V118.0 static source validation (15/15 exact transforms) remains applicable.
