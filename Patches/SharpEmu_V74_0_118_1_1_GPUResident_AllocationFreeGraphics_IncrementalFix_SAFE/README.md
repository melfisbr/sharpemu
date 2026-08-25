# SharpEmu V74.0.118.1.1 — GPU-Resident Allocation-Free Graphics Incremental Fix

This package fixes the V118.1 precheck failure reported after V118.0.1 had already been installed.

## Exact V118.1 bug

The original V118.1 patch incorrectly used the V118.0 marker as its idempotency condition:

`SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID`

Therefore a valid V118.0.1 source was reported as `V118.1 already_applied=1`, even though none
of the V118.1 allocation-free graphics structures had been inserted. The following assertion then
correctly failed on `ResidentGraphicsExecutionKeyV1181`.

V118.1.1 is intentionally incremental:
- requires V118.0.1 already installed;
- requires the V117.16 descriptor cache already present;
- does NOT reapply either layer;
- replaces exactly the seven V118.0.1 blocks that differ in V118.1;
- validates every V118.1 marker after the simulated patch and again after source installation;
- backs up the current V118.0.1 source before writing;
- build failure restores exactly that backup.

## V118.1 features installed

- shader byte-array reference fast path;
- exact `SequenceEqual` remains mandatory for a new array reference;
- allocation-free graphics state signature;
- signature is only bucket selection, never correctness identity;
- exact render target, blend and vertex-layout comparison before pipeline reuse;
- resident pipeline ownership remains with the canonical pipeline caches.

## DeviceLost safety

Unchanged:
- VkImage / VkImageView ownership;
- texture lifetime;
- guest buffer contents;
- same-queue FIFO;
- WAIT_REG_MEM / WRITE_DATA ordering;
- compute barriers;
- Pair2;
- physical VkQueue count;
- vkQueueSubmit.

The failed original V118.1 precheck did not write repository source; however this repair also safely
handles the actual V118.0.1-installed state shown by the log.
