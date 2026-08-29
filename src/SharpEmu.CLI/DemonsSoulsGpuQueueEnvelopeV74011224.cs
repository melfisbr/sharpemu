using System;
using System.Runtime.CompilerServices;

namespace SharpEmu.CLI;

/// <summary>
/// V74.0.112.2.4 - hardware-aware Demon's Souls host feed envelope.
///
/// This envelope does not increase queue counts or widen CPU->GPU buffering.
/// When Vulkan exposes the existing second physical queue, V76.3.8.3 keeps the
/// proven 18/96/4/6/12 feed limits and synchronizes graphics/compute by exact
/// guest resource hazards plus explicit guest waits instead of lane alternation.
/// V112.2.3 empirically regressed PPSA01341 when the buffering envelope itself
/// was widened from 18/96/4/6/12 to 24/96/8/6/16.
/// </summary>
// SHARPEMU_V74_0_117_1_1_7_2_CONTRACT_SAFE_STABLE_ENVELOPE
internal static class DemonsSoulsGpuQueueEnvelopeV74011224
{
    private const string Marker = "SHARPEMU_V74_0_112_2_4_GPU_QUEUE_ENVELOPE";

    [ModuleInitializer]
    internal static void Apply()
    {
        if (!IsDemonsSoulsLaunch())
        {
            return;
        }

        // V76.3.14.7.1: V76.3.1 boot ownership A/B rebased on the actual
        // V76.3.8.6 CLI envelope. This does not auto-start or skip movies.
        // RUN_4 also sets these before process start so the cached media
        // ownership decision is made in guest mode from the first access.
        Set("SHARPEMU_BINK_FORCE_GUEST", "0");
        Set("SHARPEMU_BINK_ALLOW_HOST_DECODER", "1");

        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        // V76.3.15.0 - merge do source historico ~5 FPS com a cadeia atual.
        // Profundidade volta ao source de 20/08, mas byte budget, FIFO, waits,
        // hazards e producer closure modernos permanecem.  Estes Set() sao
        // intencionalmente title-authoritative para o EXE direto nao depender
        // das variaveis do PowerShell de diagnostico.
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "1024");
        Set("SHARPEMU_QUEUE_MAX_INFLIGHT", "16");
        Set("SHARPEMU_QUEUE_LANE_BURST", "4");

        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "0");

        Set("SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN", "0");
        Set("SHARPEMU_AGC_GATE_QUANTUM_PACKETS", "32");
        Set("SHARPEMU_AGC_GATE_QUANTUM_MS", "1");
        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");
        Set("SHARPEMU_AGC_DEDICATED_NONBLOCKING_GATE", "1");
        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");
        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");

        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "300");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_ITEMS", "128");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_LIFETIME_MS", "5000");

        Set("SHARPEMU_CPU_CACHE_AWARE", "1");
        Set("SHARPEMU_CPU_CACHE_POLICY", "compact");

        // Historical V7.8.1 path: only a NATURAL guest .bk2 request may arm
        // HostMovieBridge/FFmpeg. No auto-boot and no fake completion.
        Set("SHARPEMU_BINK_FORCE_GUEST", "0");
        Set("SHARPEMU_BINK_ALLOW_HOST_DECODER", "1");
        Set("SHARPEMU_BINK_HYBRID_HOST", "1");
        Set("SHARPEMU_BINK_AUTO_BOOT", "0");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");
        // V76.3.17.0.1 - asynchronous AGC command processor.
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");
        // V76.3.17.1 - bounded compute chain.
        // Hazard classification and broad Vulkan memory barrier are unchanged.
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");

        // V76.3.16.0 - semantic FIFO reform.
        //
        // Host-only EVENT_WRITE and acquire-no-flush controls retain their exact
        // logical sequence but share physical scheduler nodes. They cannot become
        // priority-sync work and may be consumed between adjacent same-submission
        // draws without closing the Vulkan payload command buffer.
        //
        // RELEASE_MEM/EOP, WRITE_DATA producers, WAIT_REG_MEM, queue completion,
        // global/GPU->CPU visibility and presentation remain hard boundaries.
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "1");
        Set("SHARPEMU_HOST_ONLY_SIDEBAND_MAX", "64");

        // Sideband supersedes the old dequeue-time ordered microbatch.
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "0");

        // Keep the proven draw batching path. Do not re-enable the naive generic
        // FIFO payload train: V117.3.4 measured 365 draws/s vs 396 baseline.
        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");
        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "8");
        Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");
        Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");

        // Producer-backed WAIT_REG_MEM wakeups remain immediate/latch-driven.
        // Only producer-less CPU-write/deadlock fallback scans are relaxed.
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "32");
        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");
        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");
        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");

        // V76.3.8.3 structural queue contract. Keep explicit guest waits and
        // byte-range RAW/WAR/WAW hazards, but do not serialize the entire
        // opposite host lane merely because work alternates between ACB compute
        // and DCB graphics. Utility image transitions/copies now publish their
        // guest ranges to the same tracker before this policy is enabled.
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");
        Set("SHARPEMU_BINK_PROVEN_COMPUTE_PAIR2", "1");

        // CPU topology tuning is independent of guest/GPU synchronization.
        // Keep it cache-aware, physical-core-first and non-verifying in normal
        // runs; diagnostics may explicitly enable verification/logging.
        SetDefault("SHARPEMU_CPU_CACHE_AWARE", "1");
        SetDefault("SHARPEMU_CPU_CACHE_POLICY", "auto");
        SetDefault("SHARPEMU_CPU_CACHE_VERIFY", "0");

        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH", "0");
        // V76.3.5: keep the old broad V99 batching disabled. Allow only the
        // V117.7 two-dispatch pair when overlap is the sole hazard; the
        // presenter inserts a full Vulkan memory barrier at the pair edge.
        Set("SHARPEMU_COMPUTE_WRITE_OVERLAP_PAIR_BARRIER", "1");
        // V76.3.4.1 A/B regressed the V76.3.3 median and increased producer
        // waits. Restore V76.3.3 RELEASE_MEM behavior for the normal path.
        Set("SHARPEMU_DEFER_RELEASE_QUEUE_COMPLETION", "0");
        Set("SHARPEMU_CLOSED_COMPUTE_SUBMIT_GROUP", "0");
        // V74.0.117.2: scheduling precision without widening the proven envelope.
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");
        // V74.0.117.3.4: bounded presenter FIFO payload train. Scheduling
        // locality only: no cross-queue command-buffer merge, no wait bypass.
        // V117.3.4 FIFO locality measured 365 draws/s vs 396 baseline and only
        // reached train_work=3. Disable the train while retaining V117.2 waiter
        // fairness/producer precision; optimize the physical submit boundary.
        Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");
        Set("SHARPEMU_GRAPHICS_COMPUTE_SINGLE_COALESCE", "1");
        // V117.7: only the second direct compute whose guest resource ranges
        // are known and non-overlapping may share the current command buffer.
        Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");
        // SHARPEMU_V74_0_117_11_SHADER_PROCESSING_ENVELOPE
        // Cache only PVM region/protection validation for large live reads.
        // Guest bytes are copied on every TryRead and are never cached here.
        Set("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE", "1");
        // SHARPEMU_V74_0_117_12_SHADER_RESOURCE_SINGLE_COPY
        // Read-only shader global resources are described in the evaluator and
        // copied once from live guest memory directly into Vulkan staging.
        Set("SHARPEMU_SHADER_DEFER_GLOBAL_READS", "1");
        // SHARPEMU_V74_0_117_13_SHADER_GLOBAL_RESIDENCY_ENVELOPE
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "256");

        // SHARPEMU_V74_0_117_14_PRODUCER_CRITICAL_PATH_ENVELOPE
        // Normal payload queue remains 18. A temporary cap of 48 is available
        // only when AGC preindex proves that the current logical submission
        // contains a future producer for a live WAIT_REG_MEM range.
        Set("SHARPEMU_PENDING_GUEST_WORK_PRODUCER_ITEMS", "48");
        Set("SHARPEMU_PLANNED_PRODUCER_QUEUE_PRIORITY", "1");
        // V76.3.8.5: normal payload cap stays 18. With a live waiter and a
        // sync-dominated queue, allow only six extra parser-visible payloads
        // until AGC can prove the exact producer (then the existing cap 48
        // applies). Does not change max inflight or Vulkan submission policy.
        Set("SHARPEMU_PENDING_GUEST_WORK_WAITER_ITEMS", "24");

        // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_CACHE_ENVELOPE
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "2048");

        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ENVELOPE
        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "4096");

        // SHARPEMU_V76_3_3_REBAR_HOTSET_RUNTIME_SCALAR
        // V76.3.2 admitted 1024 persistent globals and drove the transient BAR
        // path into tens of thousands of allocation fallbacks. Preserve ReBAR
        // for transient traffic: only genuinely hot immutable globals become
        // resident, resident buffers use normal DEVICE_LOCAL memory after one
        // upload, and the tiny per-draw/per-compute runtime scalar SSBOs bind
        // directly from pooled mapped storage without staging/copy commands.
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "256");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "512");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "5");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_REBAR_PAUSE_FALLBACKS", "32");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "3");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "4");

        // V76.3.7.8: V76.3.7.7 measured virtually no set-associative conflict
        // evictions, so the 4-way lookup/move-to-front path was overhead without
        // evidence of a collision benefit. Return to the V76.3.5 direct-mapped
        // 4096-slot cache and shrink the shared immutable decode dictionaries.
        Set("SHARPEMU_SHADER_THREAD_CACHE_SLOTS", "4096");
        Set("SHARPEMU_SHADER_DECODE_CACHE_MAX", "4096");
        Set("SHARPEMU_SHADER_METADATA_CACHE_MAX", "4096");

        // V76.3.7.8.1: restore the exact WAIT monitor timing used by the
        // last known-good V76.3.7.7 boot. V76.3.7.8 changed only timing and
        // frontend parameters, then exposed an early guest-thread NULL execute
        // in NexusRevolution Surveillance before the GPU frontend started.
        // Keep the V76.3.7.8 frontend cache recovery, but isolate WAIT timing.
        // No wait is force-satisfied and no watched label/barrier semantics change.
        Set("SHARPEMU_WAIT_SOFT_CAP_MS", "20");
        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");
        Set("SHARPEMU_SHADER_SINGLEFLIGHT_V1190", "1");
        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");
        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "128");

        // 512 cached descriptor sets saturated in the V76.3.0 capture and
        // forced late layouts back through vkAllocateDescriptorSets. 2048 is
        // still bounded and fits the existing implementation limit (4096).
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "2048");

        // Pipeline-cache export calls vkGetPipelineCacheData and writes a
        // ~70-80 MiB blob. Keep shutdown persistence, but move periodic saves
        // out to five minutes instead of every 30 seconds.
        Set("SHARPEMU_VK_PIPELINE_CACHE_SAVE_INTERVAL_S", "300");

        // Profiling is diagnostic work. Do not force timestamp scopes and
        // pipeline timing on every Release gameplay run; RUN_4_DIAGNOSTIC can
        // explicitly opt them back in.
        SetDefault("SHARPEMU_PROFILE_RENDER", "0");
        SetDefault("SHARPEMU_PROFILE_RENDER_REPORT_S", "5");
        SetDefault("SHARPEMU_TRACE_SHADER_PIPELINE_TIMING", "0");

        // V76.3.2: strict guest-Bink ordering is a decode activity lease, not
        // a file-descriptor lifetime. 500 ms safely covers 30/60 fps YUV
        // producer cadence while releasing normal graphics/compute overlap as
        // soon as a movie decoder becomes idle.
        SetDefault("SHARPEMU_BINK_GUEST_STRICT_IDLE_MS", "500");
        Console.Error.WriteLine(
            "[V76.3.16.0][SEMANTIC_FIFO_PROFILE] " +
            "host_sideband=1 sideband_max=64 priority_sync=real-boundary-only " +
            "ordered_microbatch=off draw_buffer=8 generic_payload_train=off " +
            "wait_wake=producer-latched fullscan_fallback_ms=32 " +
            "queue=192/96 burst=4 inflight=16 single_vkqueue=1");
        // V76.3.16.0.1 - regression rollback.
        // V16 created one sideband node per logical action (no compaction)
        // and zero draw bridges, so the semantic-priority change had only
        // downside. Restore the proven V15.1 execution contract.
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");

        // V76.3.16.1.1 - dependency-driven producer scheduling only.
        // The acquire no-op experiment from V16.1 was removed completely.
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");

        // V76.3.18.0 - consolidated queue architecture.
        // The GPU decides whether dual-physical is possible: Presenter
        // requires >=2 queues in the selected family + compute + timeline.
        // SHARPEMU_V763180_FORCE_SINGLE=1 is the emergency A/B fallback.
        var forceSingleQueueV763180 = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_V763180_FORCE_SINGLE"),
            "1",
            StringComparison.Ordinal);

        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", forceSingleQueueV763180 ? "0" : "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");

        // Preserve the proven V15-V17 execution contract.
        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");
        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");
        Set("SHARPEMU_DEFER_RELEASE_QUEUE_COMPLETION", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");
        Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");

        // V76.3.19.0 - shader frontend hotset.
        // Decode/metadata caches use exact keys; set-associative L2 reduces
        // shared-cache lock traffic. Read-only globals retain generation
        // validation but enter DEVICE_LOCAL residency sooner after reuse.
        Set("SHARPEMU_SHADER_THREAD_CACHE_SETS_V190", "4096");
        Set("SHARPEMU_SHADER_DECODE_CACHE_MAX", "8192");
        Set("SHARPEMU_SHADER_METADATA_CACHE_MAX", "8192");
        Set("SHARPEMU_SHADER_SINGLEFLIGHT_V1190", "1");
        Set("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE", "1");
        Set("SHARPEMU_SHADER_DEFER_GLOBAL_READS", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "384");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "640");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_REBAR_PAUSE_FALLBACKS", "32");
        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "192");

        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "384");
        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");
        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "768");

        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "100");
        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "16");
        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");
        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");
        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");
        Set("SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN", "0");
        Set("SHARPEMU_AGC_DEDICATED_NONBLOCKING_GATE", "1");

        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "256");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "128");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "8");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "24");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "1024");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");

        Console.Error.WriteLine(
            "[V76.3.20.2][DUAL_QUEUE_DEEP_FEED] queue=256/128 burst=8 inflight=24 host_lanes=6 producer_scan=1024 compute_chain=4 dual_physical=capability-driven resource_sync=1 V20.0+V20.1=preserved");

        Console.Error.WriteLine(
            "[V76.3.20.1][EVENT_FIRST_WAIT] producer_latch=immediate dedicated_fast=1 submit_evidence=1 owner_drain=0 nonblocking_gate=1 producerless_fullscan_watchdog_ms=100 guest_wait_values=unchanged");

        Console.Error.WriteLine(
            "[V76.3.20.0][GLOBAL_RESIDENCY_CAPACITY] entries=1024 resident_mb=384 host_pool_mb=256 device_pool_mb=768 admission=V19-unchanged dual_queue=preserved waits=unchanged");

        Console.Error.WriteLine(
            "[V76.3.19.0][SHADER_FRONTEND_HOTSET_PROFILE] " +
            "l2=4wayx4096sets decode=8192 metadata=8192 " +
            "resident_shader=2048 descriptor_sets=4096 " +
            "global_residency=640/384MB admit=3 medium=2 large=2 " +
            "deferred_globals=1 rebar=1 host_buffer_cache_mb=192 " +
            "V18_queue_merge=preserved");
        // V76.3.18.1 - FAST-GPU consolidated policy.
        // SAFE=1 restores conservative cache/feed limits while preserving the
        // V18 dual-queue architecture and all correctness contracts.
        var safeGpuProfileV763181 = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_V763181_SAFE"),
            "1",
            StringComparison.Ordinal);

        // Physical queue architecture / async frontend.
        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");

        // Queue/feed depth. Windows uses a dedicated render thread, so allow it
        // to consume a deeper ready-work window without a wall-clock cap.
        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", safeGpuProfileV763181 ? "1024" : "4096");
        Set("SHARPEMU_RENDER_WORK_BUDGET_MS", "0");
        Set("SHARPEMU_RENDER_FOLLOWUP_WAIT_MS", safeGpuProfileV763181 ? "2" : "0");
        Set("SHARPEMU_RENDER_FOLLOWUP_BUDGET_MS", safeGpuProfileV763181 ? "24" : "48");
        Set("SHARPEMU_SUBMISSION_CAPACITY_WAIT_MS", safeGpuProfileV763181 ? "100" : "2");

        // Resident pipeline/module working set. This reduces pipeline recreation
        // and keeps the hot shader/layout variants resident in driver/GPU state.
        Set("SHARPEMU_VK_PIPELINE_CACHE", "1");
        Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", safeGpuProfileV763181 ? "512" : "1024");
        Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", safeGpuProfileV763181 ? "256" : "1024");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", safeGpuProfileV763181 ? "512" : "2048");

        // VRAM/device-local residency. These are caches with existing eviction
        // and unsupported-device fallback; they do not pin all guest memory.
        Set("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");
        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");
        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", safeGpuProfileV763181 ? "512" : "1024");
        Set("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB", safeGpuProfileV763181 ? "256" : "512");
        Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", safeGpuProfileV763181 ? "512" : "1024");
        Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", safeGpuProfileV763181 ? "3072" : "4096");

        // Existing scheduler improvements remain authoritative.
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");
        Set("SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY", "1");
        Set("SHARPEMU_DEFERRED_FOLLOWUP_SPIN_BREAK", "1");
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");
        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");

        Console.Error.WriteLine(
            "[V76.3.18.1][FAST_GPU_RESIDENT_PROFILE] " +
            $"mode={(safeGpuProfileV763181 ? "SAFE" : "FAST")} " +
            "dual_queue=capability async_agc=1 chain4=1 cb_pool=256 " +
            $"work_per_render={(safeGpuProfileV763181 ? 1024 : 4096)} " +
            $"capacity_wait_ms={(safeGpuProfileV763181 ? 100 : 2)} " +
            $"gfx_pipeline_cache={(safeGpuProfileV763181 ? 512 : 1024)} " +
            $"compute_pipeline_cache={(safeGpuProfileV763181 ? 256 : 1024)} " +
            $"descriptor_sets={(safeGpuProfileV763181 ? 512 : 2048)} " +
            $"device_buffer_mb={(safeGpuProfileV763181 ? 512 : 1024)} " +
            $"guest_buffer_mb={(safeGpuProfileV763181 ? 256 : 512)} " +
            $"sampled_image_mb={(safeGpuProfileV763181 ? 512 : 1024)} " +
            $"texture_cache_mb={(safeGpuProfileV763181 ? 3072 : 4096)}");
        Console.Error.WriteLine(
            "[V76.3.18.0][RPCS3_QUEUE_MERGE] " +
            $"mode={(forceSingleQueueV763180 ? "single-safe" : "capability-dual-resource-safe")} " +
            "dcb=graphics-lane acb=compute-lane timeline=1 range_hazards=1 " +
            "async_agc=1 compute_chain=4 cb_pool=256 " +
            "wait_fallback=16ms sideband=off microbatch=on " +
            "queue=192/96 burst=4 inflight=16");
        Console.Error.WriteLine(
            "[V76.3.17.1][COMPUTE_CHAIN4_BROAD_PROFILE] " +
            "chain_max=4 edge_validation=v1177-adjacent " +
            "barrier=all-commands-memory-rw unchanged=waits+hazards+visibility " +
            "async_agc=v1701 sideband=off microbatch=on");
        Console.Error.WriteLine(
            "[V76.3.17.0.1][ASYNC_AGC_CP_ADAPTIVE] " +
            "source=current-434d7980 guest_submit=publish-only " +
            "command_processor=dedicated-thread ingress_max=1024 " +
            "pm4_parser=existing waits=unchanged hazards=unchanged " +
            "presenter=current-branch");
        Console.Error.WriteLine(
            "[V76.3.16.1.1][DEPENDENCY_SLICED_PRODUCER] " +
            "slices=8x128 pause_us=1000 lifetime_ms=5000 same_queue_fifo=1 " +
            "sibling_fairness=1 acquire_fastpath=off sideband=off microbatch=on " +
            "queue=192/96 burst=4 inflight=16 single_vkqueue=1");
        Console.Error.WriteLine(
            "[V76.3.16.0.1][SIDEBAND_REGRESSION_ROLLBACK] " +
            "presenter=v15.1-exact host_sideband=0 ordered_microbatch=1 " +
            "wait_fullscan_ms=16 queue=192/96 burst=4 inflight=16 " +
            "safe_memcpy=preserved waits=preserved hazards=preserved");
        Console.Error.WriteLine(
            "[V76.3.15.1][BOOT_LANE6_SAFE_MEMCPY] " +
            "queue=192/96 burst=4 inflight=16 reserved_lanes=6 " +
            "single_vkqueue=1 safe_memcpy=chunked-read-write " +
            "waits=unchanged hazards=unchanged bink=unchanged");
        Console.Error.WriteLine(
            "[V76.3.14.7.1_BOOT_BINK_OWNERSHIP_REBASE] " +
            "owner=guest-v7631-control host_decoder=off process_env_prearmed=diagnostic " +
            "auto_boot=off queue_wait_resource_stack=preserved");
        Console.Error.WriteLine(
            "[V76.3.2][PERF_LANE_RESTORE] " +
            "bink_strict_activity_lease_ms=500 stale_fd_serialization=off " +
            "normal_graphics_compute_overlap=restore-after-bink-idle");

        Console.Error.WriteLine(
            "[V76.3.8.5][WAITER_PROGRESS_RESERVE] " +
            "normal_payload_items=18 waiter_progress_items=24 planned_producer_items=48 " +
            "activation=live-waiter+sync-majority+unproven-producer " +
            "fifo=unchanged inflight=12 hazards=unchanged fences=unchanged " +
            "guest_wait_values=unchanged");

        Console.Error.WriteLine(
            "[V76.3.8.4.1.1][ADAPTIVE_REBASE_RECOVERY] " +
            "source=current-weighted-closure wait_full_scan=v76383 " +
            "release_mem=v76383 visibility_unblock=exact-fence-scheduler-only " +
            "resource_retirement=unchanged guest_semantics=unchanged");

        Console.Error.WriteLine(
            "[V76.3.8.3][STRUCTURAL_QUEUE_ORDER] " +
            "dual_queue=resource-scoped utility_access_tracking=1 " +
            "bink_strict=resource-scoped bink_pair=proven-max2 " +
            "wait_reg_mem=unchanged write_data=unchanged release_mem=unchanged " +
            "cpu_cache=auto guest_semantics=preserved");

        Console.Error.WriteLine(
            "[V76.3.5][BARRIERED_OVERLAP_PAIR] " +
            "release_eop_defer=0 broad_barrier_batch=0 " +
            "write_overlap_pair=1 max_compute_pair=2 " +
            "barrier=all-commands-memory-rw hazards=conservative");

        Console.Error.WriteLine(
            "[V76.3.7.5][MEMORY_HOTPATH_RECOVERY] " +
            "texture_storage_alias=1 dstselect_sampler_reuse=1 " +
            "stable_probe=3x64B host_cache_mb=128 bink_policy=preserved");

        Console.Error.WriteLine(
            "[V76.3.7.7][STABLE_PRODUCER_VIEW_DEDUP] " +
            "producer_priority=saturation-gated producer_items=48 same_queue_fifo=1 " +
            "global_residency=512/256MB stable_probe=3x64B admit=3-5 " +
            "pvm_read_slots=1024 debug_sgpr_selfcheck=once " +
            "local_view_payload_dedup=1 bink_policy=preserved " +
            "wait_satisfaction=unchanged barriers=unchanged hazards=unchanged");

        Console.Error.WriteLine(
            "[V76.3.7.8][FRONTEND_STABILITY_RECOVERY] " +
            "shader_l2=direct/4096 shared_decode=4096 shared_metadata=4096 " +
            "wait_timing=overridden-by-v763781 producer_policy=v76377-stable " +
            "view_payload_dedup=preserved bink_policy=preserved");

        Console.Error.WriteLine(
            "[V76.3.7.8.1][WAIT_TIMING_RACE_RECOVERY] " +
            "wait_monitor_max_ms=4 wait_soft_cap_ms=20 " +
            "known_good_timing=v76377 frontend=v76378-direct4096 " +
            "wait_satisfaction=unchanged barriers=unchanged hazards=unchanged " +
            "bink_policy=preserved");

        Console.Error.WriteLine(
            "[V76.3.6][MAX_P0_RECOVERY] shader_l2=overridden-by-v76378 " +
            "shared_decode=overridden-by-v76378 global_residency=overridden-by-v76377 " +
            "pvm_read_slots=overridden-by-v76377 wait_monitor=overridden-by-v763781 scratch_bank=32");

        Console.Error.WriteLine(
            "[V76.3.3][REBAR_HOTSET_SCALAR] " +
            "runtime_scalar_direct=1 scalar_max_kb=8 host_cache_mb=128 " +
            "residency=overridden-by-v76377 " +
            "resident_rebar=off rebar_pause_fallbacks=32 descriptor_sets=2048 " +
            "pipeline_cache_save_s=300 profiling=opt-in");

        Console.Error.WriteLine(
            "[V74.0.117.4][SUBMIT_BOUNDARY_REFORM] " +
            "fifo_payload_train=1 graphics_compute_single_coalesce=1 " +
            "one_compute_per_batch=1 candidate_0x4459A200_join=0 " +
            "queue=192/96 burst=4 inflight=16 dual_physical=single " +
            "barriered=0 closed_group=0 write_bypass=0");
        Console.Error.WriteLine(
            "[V74.0.117.7][STRUCTURAL_SUBMIT_REFORM] " +
            "disjoint_compute_pair2=1 max_compute_per_submit=2 " +
            "pair_rule=known-nonoverlap same_queue_submission=1 " +
            "global_write_join=0 metadata_join=0 indirect_join=0 " +
            "device_lost_candidate_join=0 provenance_runtime_optin=1 " +
            "barriered=0 closed_group=0 dual_physical=resource-scoped");
        Console.Error.WriteLine(
            "[V76.3.15.0][5FPS_BASELINE_MERGE] " +
            "donor=src-20260820-133228 donor_perf=v763781 " +
            "pending=192/96 burst=4 inflight=16 reserved_lanes=6 " +
            "single_vkqueue=1 closure128=1 wait_owner_drain=0 " +
            "bink=natural-request-host-ffmpeg auto_boot=off");
        Console.Error.WriteLine(
            "[V74.0.117.2][QUEUE_PRECISION] " +
            "queue_size_merged=192/96 burst=4 max_inflight=16 " +
            "fifo_producer_assist=1 fifo_scan_depth=512 " +
            "sync_priority_real_wait_only=1 write_control_lane=0");

        Console.Error.WriteLine(
            "[V74.0.112.2.4][GPU_QUEUE_ENVELOPE] " +
            "active=1 physical_vkqueue_policy=single " +
            "pending_items=192 pending_mb=96 burst=4 reserved_lanes=6 " +
            "max_inflight=16 barriered=0 closed_group=0");
        // V76.3.20.3 - keep real dual queues/residency but recover the pressure
        // envelope that reached main loop much earlier than V20.2.
        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_PENDING_GUEST_WORK_PRODUCER_ITEMS", "48");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");
        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");
        Set("SHARPEMU_WAIT_SOFT_CAP_MS", "20");
        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");

        Console.Error.WriteLine(
            "[V76.3.20.3][BALANCED_DUAL_QUEUE_RECOVERY] " +
            "queue=192/96 burst=4 inflight=16 host_lanes=6 producer_scan=512 " +
            "dual_physical=1 resource_sync=1 wait_fullscan=16ms " +
            "V20.0_residency=preserved V20.1_100ms=reverted V20.2_deepfeed=reverted");
        // V76.3.20.4 - use existing narrow producer fast paths only.
        // WRITE_DATA must be CPU-resident, exact watched range and cross-queue.
        // Same-queue ordering, RELEASE_MEM, DMA and GPU readback remain unchanged.
        Set("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");
        Set("SHARPEMU_CROSS_QUEUE_WATCHED_INLINE_WRITE", "1");
        Set("SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY", "1");
        Set("SHARPEMU_UPSTREAM003_DIRECT_DRAIN", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");

        Console.Error.WriteLine(
            "[V76.3.20.4][WATCHED_WRITE_PRODUCER_FASTPATH] " +
            "packet_position=1 cross_queue_inline=1 known_producer_visibility_elide=1 " +
            "direct_drain=1 same_queue_fifo=preserved release_mem=unchanged dma=unchanged " +
            "queue=192/96 burst=4 inflight=16 dual_physical=1");
        // V76.3.20.5 - expand only the proven immutable DEVICE_LOCAL hotset.
        // V20.0 saturated 1024 entries at ~371.6 MiB with zero budget fallback.
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1536");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");
        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");
        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "1024");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");

        // Preserve V19 admission thresholds; do not make one-off globals resident.
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");

        Console.Error.WriteLine(
            "[V76.3.20.5][RESIDENT_GLOBAL_HOTSET1536] " +
            "entries=1536 resident_mb=512 host_pool_mb=256 device_pool_mb=1024 " +
            "resident_shader=2048 descriptor_sets=4096 admission=V19 " +
            "queue=192/96 burst=4 inflight=16 dual_physical=1 V20.4=preserved");

        // ============================================================
        // V76.3.18.5 - ADAPTIVE FULL PERFORMANCE MERGE
        // Final title-authoritative policy. Historical markers above
        // remain for provenance, but these values are the active contract.
        // ============================================================
        var forceSingleV763185 = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_V763185_FORCE_SINGLE"),
            "1",
            StringComparison.Ordinal);
        var conservativeWait16V763185 = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_V763185_WAIT_SCAN_16MS"),
            "1",
            StringComparison.Ordinal);

        // REAL GPU QUEUE TOPOLOGY
        // Presenter still capability-checks queue-count/compute/timeline.
        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", forceSingleV763185 ? "0" : "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");

        // FEED ENVELOPE — preserve stable V15-V17 contract.
        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");
        Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");
        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");
        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "8");
        Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_COMPUTE_WRITE_OVERLAP_PAIR_BARRIER", "1");
        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH", "0");
        Set("SHARPEMU_CLOSED_COMPUTE_SUBMIT_GROUP", "0");

        // ASYNC AGC — guest submit publishes, dedicated CP parses.
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");

        // WAIT / PRODUCER — normal path is evidence/latch driven.
        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");
        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");
        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");
        Set("SHARPEMU_AGC_GATE_QUANTUM_PACKETS", "32");
        Set("SHARPEMU_AGC_GATE_QUANTUM_MS", "1");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", conservativeWait16V763185 ? "16" : "32");
        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");
        Set("SHARPEMU_WAIT_SOFT_CAP_MS", "20");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");
        Set("SHARPEMU_DEFER_RELEASE_QUEUE_COMPLETION", "1");

        // The failed V16 sideband stays disabled.
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");

        // SHADER FRONTEND / RESIDENCY
        Set("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE", "1");
        Set("SHARPEMU_SHADER_DEFER_GLOBAL_READS", "1");
        Set("SHARPEMU_SHADER_SINGLEFLIGHT_V1190", "1");
        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");

        // V17.1 saturated global residency at 512 entries (~206 MiB)
        // with thousands of budget fallbacks. Keep the proven hot-admit
        // policy but double the bounded entry/VRAM budget.
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "5");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "3");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "4");

        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");
        Set("SHARPEMU_SHADER_THREAD_CACHE_SLOTS", "4096");
        Set("SHARPEMU_SHADER_DECODE_CACHE_MAX", "4096");
        Set("SHARPEMU_SHADER_METADATA_CACHE_MAX", "4096");

        // Parallel compile/prewarm and allocation caches.
        Set("SHARPEMU_VK_PARALLEL_STAGE_COMPILE", "1");
        Set("SHARPEMU_SPIRV_PREWARM_MAX", "512");
        Set("SHARPEMU_SPIRV_PREWARM_MB", "128");
        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");
        Set("SHARPEMU_VK_PIPELINE_CACHE_SAVE_INTERVAL_S", "600");

        // CPU guest lanes: proven compact policy, not spread.
        Set("SHARPEMU_CPU_CACHE_AWARE", "1");
        Set("SHARPEMU_CPU_CACHE_POLICY", "compact");
        Set("SHARPEMU_CPU_CACHE_VERIFY", "0");
        Set("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT", "16");
        Set("SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT", "8");

        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");
        Set("SHARPEMU_HOST_TARGET_FPS", "60");

        // Normal gameplay must not pay diagnostic/logging cost.
        // RUN_4 explicitly overrides the small set needed for profiling.
        SetDefault("SHARPEMU_PROFILE_RENDER", "0");
        SetDefault("SHARPEMU_TRACE_FRAME_STATS", "0");
        SetDefault("SHARPEMU_TRACE_SPIRV_CACHE", "0");
        SetDefault("SHARPEMU_TRACE_COMPUTE_PHASES", "0");
        SetDefault("SHARPEMU_TRACE_DRAW_PHASES", "0");
        SetDefault("SHARPEMU_TRACE_DRAW_RESOURCE_PHASES", "0");
        SetDefault("SHARPEMU_TRACE_ORDERED_ACTION_LATENCY", "0");
        SetDefault("SHARPEMU_TRACE_GPU_SUBMISSION_LATENCY", "0");
        SetDefault("SHARPEMU_TRACE_GUEST_WORK_COMPLETION", "0");
        SetDefault("SHARPEMU_TRACE_RESOURCE_DEPENDENCIES", "0");
        SetDefault("SHARPEMU_TRACE_QUEUE_OPTIMIZER", "0");
        SetDefault("SHARPEMU_TRACE_PM4_PREINDEX_BULK", "0");
        SetDefault("SHARPEMU_TRACE_PRESENT_CADENCE", "0");
        SetDefault("SHARPEMU_TRACE_SHADER_PIPELINE_TIMING", "0");
        SetDefault("SHARPEMU_TRACE_VULKAN_HOTPATH_DIAGNOSTICS", "0");
        SetDefault("SHARPEMU_TRACE_AGC_HOTPATH_DIAGNOSTICS", "0");

        Console.Error.WriteLine(
            "[V76.3.18.5][ADAPTIVE_FULL_MERGE] " +
            $"queue_mode={(forceSingleV763185 ? "single-safe" : "dual-capability-resource")} " +
            $"wait_fullscan_ms={(conservativeWait16V763185 ? 16 : 32)} " +
            "async_agc=1 chain4=1 cb_pool=256 fence_pool=256 " +
            "global_residency=1024/512MB descriptor_cache=4096 " +
            "resident_shader=2048 parallel_compile=1 prewarm=512/128MB " +
            "host_buffer_cache_mb=256 cpu=compact16/8 " +
            "sideband=off microbatch=on safe_memcpy=1");

        // ============================================================
        // V76.3.21.0 - FORWARD MAX THROUGHPUT ADAPTIVE MERGE
        // Final authoritative profile after every historical bootstrap.
        // ============================================================
        var safeModeV763210 = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_V763210_SAFE_MODE"),
            "1",
            StringComparison.Ordinal);

        // Physical queue architecture: keep V18/V20 real dual queue.
        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");

        // Queue envelope proven stable across V20.3-V20.5.
        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");
        Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");

        // Guest CPU -> async AGC CP separation.
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");

        // Persistent command recording / bounded compute continuity.
        Set("SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210", safeModeV763210 ? "2" : "3");
        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");
        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", safeModeV763210 ? "8" : "16");
        Set("SHARPEMU_COMPUTE_SHARED_BATCH", "1");
        Set("SHARPEMU_COMPUTE_RESOURCE_SETUP_COALESCE", "1");
        Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH", "0");
        Set("SHARPEMU_CLOSED_COMPUTE_GROUP", "0");

        // Collapse large 27x15x72-style dispatches into fewer host
        // command records. Device workgroup limits remain authoritative.
        Set("SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE", "1");
        Set("SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE_MAX_GROUPS", "65536");
        Set("SHARPEMU_COMPUTE_Z_SLICES_PER_SUBMISSION", safeModeV763210 ? "64" : "128");

        // V20.4 watched producer fastpath: exact producer evidence first.
        Set("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");
        Set("SHARPEMU_CROSS_QUEUE_WATCHED_INLINE_WRITE", "1");
        Set("SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY", "1");
        Set("SHARPEMU_UPSTREAM003_DIRECT_DRAIN", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");

        // Event/evidence-driven wait path. Full memory scan remains a
        // producer-less CPU-write/watchdog fallback, not normal progress.
        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");
        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");
        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", safeModeV763210 ? "16" : "32");
        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");
        Set("SHARPEMU_WAIT_SOFT_CAP_MS", "20");
        Set("SHARPEMU_AGC_GATE_QUANTUM_PACKETS", "32");
        Set("SHARPEMU_AGC_GATE_QUANTUM_MS", "1");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");

        // Dependency-driven producer continuation.
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");
        Set("SHARPEMU_DEFER_RELEASE_QUEUE_COMPLETION", "1");

        // V20.5 resident global hot set / prepared immutable resources.
        Set("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE", "1");
        Set("SHARPEMU_SHADER_DEFER_GLOBAL_READS", "1");
        Set("SHARPEMU_SHADER_RESOURCE_SINGLEFLIGHT", "1");
        Set("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");
        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");
        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");
        Set("SHARPEMU_NONBLOCKING_GLOBAL_REFRESH", "1");

        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", safeModeV763210 ? "1024" : "1536");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");

        // Resident shaders + descriptor/pipeline state.
        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");
        Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", safeModeV763210 ? "512" : "1024");
        Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", safeModeV763210 ? "256" : "512");
        Set("SHARPEMU_VK_PIPELINE_CACHE", "1");
        Set("SHARPEMU_VK_PIPELINE_CACHE_SAVE_INTERVAL_S", "600");

        // Shader frontend caches / compilation separation.
        Set("SHARPEMU_SHADER_RESOURCE_THREAD_CACHE", "4096");
        Set("SHARPEMU_SHADER_SHARED_DECODE_CACHE_ENTRIES", "4096");
        Set("SHARPEMU_SHADER_SHARED_METADATA_CACHE_ENTRIES", "4096");
        Set("SHARPEMU_VK_PARALLEL_STAGE_COMPILE", "1");
        Set("SHARPEMU_SPIRV_PREWARM_MAX", "512");
        Set("SHARPEMU_SPIRV_PREWARM_MB", "128");

        // Reusable host/VRAM working sets. These are caps, not eager
        // allocation requests; guest visibility rules still choose memory.
        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");
        Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", safeModeV763210 ? "768" : "1024");
        Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", safeModeV763210 ? "3072" : "4096");
        Set("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB", safeModeV763210 ? "384" : "512");
        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "1024");

        // Ryzen 9 3900: keep proven compact policy rather than spreading
        // shader workers over every SMT lane.
        Set("SHARPEMU_CPU_CACHE_POLICY", "compact");
        Set("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT", "16");
        Set("SHARPEMU_RENDERER_RESOURCE_NATIVE_WORKER_MAX_CONCURRENT", "8");

        // Failed/obsolete experiments remain explicitly disabled.
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");

        // Remove census/debug work from normal hot paths.
        Set("SHARPEMU_TRACE_SHADER_PIPELINE_TIMING", "0");
        Set("SHARPEMU_TRACE_RESOURCE_DEPENDENCIES", "0");
        Set("SHARPEMU_COMPUTE_PAIR_HAZARD_CENSUS", "0");
        Set("SHARPEMU_COMPUTE_RESOURCE_OVERLAP_CENSUS", "0");
        Set("SHARPEMU_TRACE_DRAW_RESOURCE_PHASES", "0");
        Set("SHARPEMU_TRACE_GUEST_IMAGE_SHADER_ADDRS", "0");
        Set("SHARPEMU_LOG_AGC_SHADER", "0");
        Set("SHARPEMU_LOG_VK_SHADER", "0");
        Set("SHARPEMU_LOG_VK_COMPUTE_RESOURCES", "0");
        Set("SHARPEMU_LOG_VK_RESOURCES", "0");

        Console.Error.WriteLine(
            "[V76.3.21.0][FORWARD_MAX_MERGE] " +
            $"mode={(safeModeV763210 ? "safe" : "max")} " +
            $"frames_in_flight={(safeModeV763210 ? 2 : 3)} dual_queue=resource-timeline async_agc=1 " +
            $"draw_cb={(safeModeV763210 ? 8 : 16)} chain4=1 compute_z={(safeModeV763210 ? 64 : 128)} " +
            $"wait_fullscan_ms={(safeModeV763210 ? 16 : 32)} watched_producer=1 " +
            $"residency_entries={(safeModeV763210 ? 1024 : 1536)} residency_mb=512 " +
            "resident_shader=2048 descriptors=4096 pipeline_cache=1024/512 " +
            "prewarm=512/128MB resource_cache=256/1024/4096/512/1024 " +
            "nonblocking_global_refresh=1 cpu=compact16/8 hot_traces=off");

        // V76.3.21.1 - consolidated maximum critical-path profile.
        // SHARPEMU_V763211_DISABLE=1 restores the V21.0 policy
        // without source rollback for immediate A/B.
        var disableV763211 = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_V763211_DISABLE"),
            "1",
            StringComparison.Ordinal);

        if (!disableV763211)
        {
            // Keep the proven balanced queue envelope. V20.2 deep feed
            // (256/128, burst8, inflight24) remains intentionally reverted.
            Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
            Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
            Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
            Set("SHARPEMU_RESERVED_HOST_LANES", "6");
            Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");

            // Real dual Vulkan lanes + range/timeline synchronization.
            Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");
            Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
            Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
            Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");

            // Async AGC command processor remains authoritative.
            Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
            Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");

            // Producer critical path: discover earlier and keep the
            // exact producer queue moving FIFO until the watched packet.
            Set("SHARPEMU_PLANNED_PRODUCER_QUERY_SCAN", "256");
            Set("SHARPEMU_AGED_PRODUCER_QUERY_SCAN", "1024");
            Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
            Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "4096");
            Set("SHARPEMU_PLANNED_PRODUCER_QUEUE_PRIORITY", "1");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE", "1");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "50");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_ITEMS", "128");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_LIFETIME_MS", "5000");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN", "4096");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "16");
            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "250");

            // Event-first wait wakeups. Full scan remains only a bounded
            // producer-less/CPU-write recovery path.
            Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "32");
            Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");
            Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");
            Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");
            Set("SHARPEMU_UPSTREAM003_DIRECT_DRAIN", "1");
            Set("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");
            Set("SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY", "1");
            Set("SHARPEMU_KYTY_PM4_BLOCKED_SCHEDULER", "1");
            Set("SHARPEMU_KYTY_INLINE_WRITE_DATA", "1");

            // Larger safe command trains. Every compute edge still passes
            // the existing hazard proof and retains the broad barrier.
            Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "8");
            Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");
            Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "32");
            Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");
            Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
            Set("SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX", "64");
            Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");
            Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
            Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");
            Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "4096");
            Set("SHARPEMU_COMPUTE_Z_SLICES_PER_SUBMISSION", "128");
            Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");
            Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");
            Set("SHARPEMU_DEFERRED_FOLLOWUP_SPIN_BREAK", "1");
            Set("SHARPEMU_RELEASE_MEM_QUEUE_COMPLETION_ONLY", "1");
            Set("SHARPEMU_LOCAL_TEXTURE_PAYLOAD_DEDUP", "1");

            // Keep V21 cache/residency capacities. Current traces show
            // these caches are not capacity-bound, so no blind VRAM growth.
            Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
            Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");
            Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", "1024");
            Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", "512");
            Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");
            Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");
            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1536");
            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");
            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");
            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");
            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");
            Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");
            Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "1024");
            Set("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB", "512");
            Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", "1024");
            Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", "4096");
            Set("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");
            Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
            Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");

            // Preserve the title-specific memory safety fix.
            Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");
        }

        Console.Error.WriteLine(
            "[V76.3.21.2][GLOBAL_SNAPSHOT_BOUNDS] " +
            "partial_snapshot=live-deferred no_span_overrun=1 " +
            "nonblocking_global_refresh=preserved " +
            "dual_queue=preserved async_agc=preserved compute_chain8=preserved " +
            "residency1536=preserved draw_cb32=preserved waits=preserved");
        Console.Error.WriteLine(
            "[V76.3.21.1][MAX_CRITICAL_PATH_MERGE] " +
            $"mode={(disableV763211 ? "V21-baseline" : "max-critical")} " +
            "queue=192/96 burst=4 inflight=16 dual=resource-timeline async_agc=1 " +
            "producer_query=256/1024 producer_scan=4096 closure_age_ms=50 " +
            "closure=16x128/250us wait_fullscan_ms=32 " +
            "compute_chain=8 draw_cb=32 ordered_microbatch=64 " +
            "residency=1536/512MB shaders=2048 descriptors=4096 " +
            "sideband=off control_lane=off safe_memcpy=1");
        // V76.3.21.3 - guest progress recovery.
        // V21.2 drains Vulkan cleanly but stops guest DCB/ACB production
        // before the first natural ps_studios_logo.bk2 open. Restore the
        // V17.1 scheduler envelope that reached natural Bink requests,
        // while preserving V18+ dual queues and all V21.2 safety fixes.
        Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "1024");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_PENDING_GUEST_WORK_PRODUCER_ITEMS", "48");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "300");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_ITEMS", "128");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX", "32");
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");
        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "8");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");

        // Keep the structural improvements that are already proven safe.
        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_SAFE_MEMCOPY_V763151", "1");

        // Do not mask the regression with host-injected boot movies.
        // The success condition is the guest opening the Bink naturally.
        Set("SHARPEMU_BINK_AUTO_BOOT", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_GPU", "0");
        Set("SHARPEMU_DS_TITLE_TIMELINE_PASSTHROUGH", "1");

        Console.Error.WriteLine(
            "[V76.3.21.3][GUEST_PROGRESS_RECOVERY] " +
            "work_per_render=1024 producer_scan=512 " +
            "closure=300ms/8x128/1000us microbatch=32 " +
            "compute_chain=4 draw_cb=8 wait_fullscan=16ms " +
            "dual_queue=preserved async_agc=preserved " +
            "snapshot_v212=preserved residency=preserved " +
            "bink=natural-request-only auto_boot=off");

    }


    private static bool IsDemonsSoulsLaunch()
    {
        foreach (var arg in Environment.GetCommandLineArgs())
        {
            if (arg.Contains("PPSA01341", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        var titleId = Environment.GetEnvironmentVariable("SHARPEMU_TITLE_ID");
        return string.Equals(titleId, "PPSA01341", StringComparison.OrdinalIgnoreCase);
    }

    private static void Set(string name, string value) =>
        Environment.SetEnvironmentVariable(name, value, EnvironmentVariableTarget.Process);

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)))
        {
            Set(name, value);
        }
    }

    internal static string VersionMarker => Marker;
}
