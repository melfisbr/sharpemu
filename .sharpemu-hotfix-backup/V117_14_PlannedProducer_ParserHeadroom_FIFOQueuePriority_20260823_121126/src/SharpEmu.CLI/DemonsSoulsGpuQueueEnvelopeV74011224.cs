using System;
using System.Runtime.CompilerServices;

namespace SharpEmu.CLI;

/// <summary>
/// V74.0.112.2.4 - hardware-aware Demon's Souls host feed envelope.
///
/// This does NOT create more Vulkan queues. The Presenter currently requests one
/// physical VkQueue. These values only bound CPU->GPU buffering and in-flight
/// submissions. V112.2.3 empirically regressed PPSA01341 when the envelope was
/// widened from 18/96/4/6/12 to 24/96/8/6/16.
///
/// Keep the best-known stable envelope until a second physical VkQueue is
/// introduced together with explicit cross-queue synchronization.
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

        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "18");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "12");
        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH", "0");
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
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");
        Console.Error.WriteLine(
            "[V74.0.117.4][SUBMIT_BOUNDARY_REFORM] " +
            "fifo_payload_train=1 graphics_compute_single_coalesce=1 " +
            "one_compute_per_batch=1 candidate_0x4459A200_join=0 " +
            "queue=18/96 burst=4 inflight=12 dual_physical=0 " +
            "barriered=0 closed_group=0 write_bypass=0");
        Console.Error.WriteLine(
            "[V74.0.117.7][STRUCTURAL_SUBMIT_REFORM] " +
            "disjoint_compute_pair2=1 max_compute_per_submit=2 " +
            "pair_rule=known-nonoverlap same_queue_submission=1 " +
            "global_write_join=0 metadata_join=0 indirect_join=0 " +
            "device_lost_candidate_join=0 provenance_runtime_optin=1 " +
            "barriered=0 closed_group=0 dual_physical=0");
        Console.Error.WriteLine(
            "[V74.0.117.2][QUEUE_PRECISION] " +
            "queue_size_unchanged=18/96 burst=4 max_inflight=12 " +
            "fifo_producer_assist=1 fifo_scan_depth=512 " +
            "sync_priority_real_wait_only=1 write_control_lane=0");

        Console.Error.WriteLine(
            "[V74.0.112.2.4][GPU_QUEUE_ENVELOPE] " +
            "active=1 physical_vkqueue_policy=single-until-explicit-sync " +
            "pending_items=18 pending_mb=96 burst=4 reserved_lanes=6 " +
            "max_inflight=12 barriered=0 closed_group=0");
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

    internal static string VersionMarker => Marker;
}
