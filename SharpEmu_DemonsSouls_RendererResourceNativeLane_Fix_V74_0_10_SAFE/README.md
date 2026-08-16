# SharpEmu Demon's Souls — Renderer/Resource Native Lane V74.0.10 SAFE

V74.0.9 proved the GPU/frontend stall is no longer a memory, compute,
FailFast, shader, or device-loss problem.

The scheduler/native snapshots expose a deterministic concurrency defect:

- Core.Res.TaskManager: 413 Running/ExecutorActive snapshots, imports stayed 4.
- NexusRevolution Event: imports 28 -> 12102.
- NexusRevolution Surveillance: imports 152 -> 70557.
- all three use RequiresNativeGuestWorker().
- RunGuestEntryStub() used one SemaphoreSlim with default capacity 2.

A guest thread is marked Running before entering that semaphore, so
TaskManager can look Running while its host executor is actually parked at the
two-slot native-worker gate.

V74.0.10 separates the long-lived renderer/resource family into its own raw
NativeGuestExecutor lane, default capacity 8:

- HighGraphics
- Core.Res.*
- NexusRevolution Event
- NexusRevolution Surveillance

The historical TBB/native burst gate remains 2. No thread is moved back to
managed-inline execution, so V74.0.3.4 FailFast hardening remains intact.
Generic pthreads keep the V73.20.4.1 per-guest dedicated executor path.

NativeWorker baseline SHA:
B0301DABA2892BFC47D9F6A947664B2147ECCA173BD6DA8EADB58F6414929BCF

V74.0.10 NativeWorker SHA:
F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38

The diagnostic remains one comprehensive run: memory, GPU, thread snapshots,
native-lane occupancy/wait time, EVENT_FASTPATH, presenter timeline, 0x45D,
compute, FailFast, device loss and natural Bink/YUV are captured together.
