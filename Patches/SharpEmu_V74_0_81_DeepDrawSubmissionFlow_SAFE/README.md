# SharpEmu V74.0.81 — Deep Draw Submission Flow SAFE

Target: the measured 2 FPS bottleneck after V74.0.78.3, without replacing the accumulated presenter.

## Why this patch exists
The V74.0.78.3 runtime proved sampler pre-snapshot aliasing works, but the renderer still showed:
- PAYLOAD_BATCH_SUBMIT count=8192 / total_work=8623 / avg=1.05 work per physical submit.
- no observed V74.0.43 queue-submission burst in the captured run.
- capacity yield at pending_gpu=8.
- slow waits up to ~5.866 s while the producer is real and eventually completed.
- queue backpressure retaining 129–342 MiB while the queue itself contains only sync work.

## Changes
1. **Bounded same-submission queue burst: default 8** (the existing environment override now accepts 1 to restore legacy round-robin).
2. **Compute shared-batch flush repair:** removes the two unconditional flush boundaries inside `ExecuteComputeDispatchCore` when the already-proven V74.0.56.20 preserve-batch path is active. Standalone/indirect/multi-submit compute still flushes before its own command buffer.
3. **Queued vs in-flight byte accounting:** once a work item leaves the software queue, its payload bytes move to a bounded in-flight counter instead of continuing to block parser queue admission until rendering completes. Deferred/requeued work moves the bytes back exactly once.
4. Adds diagnostics for batch average, queue bursts, in-flight transitions, waits, backpressure, capacity, and DCC reject counters.

## Safety / A-B rollback switches
Without rolling back source, legacy behavior can be approximated for A/B with:
- `SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST=1`
- `SHARPEMU_PRESERVE_PAYLOAD_BATCH=0`
- `SHARPEMU_QUEUE_SEPARATE_INFLIGHT_BYTES=0`

No guest fence, WRITE_DATA value, WAIT condition, PM4 order within a guest queue, shader, DCC provenance rule, or texture format is synthesized/relaxed.

This package is structural and does not use a rigid source SHA gate. RUN_3 backs up the current `VulkanVideoPresenter.cs` and automatically restores it if the build fails.
