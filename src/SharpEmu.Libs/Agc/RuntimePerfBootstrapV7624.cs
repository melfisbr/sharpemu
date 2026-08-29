// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.4: process-wide defaults that unlock waits, gate quantum, shader cache.

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Agc;

internal static class RuntimePerfBootstrapV7624
{
    internal const string Marker = "V76.2.4_PERF_BOOTSTRAP";

    [ModuleInitializer]
    internal static void Initialize()
    {
        // Dedicated wait consumer must stay on.
        SetDefault("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");

        // V76.3.14.5_BOOT_WAIT_POLICY_RECOVERY
        // Keep the dedicated producer->waiter consumer, but stop yielding the
        // AGC Gate every eight packets.  The underlying AgcExports policy uses
        // a 32-packet parser quantum on Windows/Linux; the earlier 8-packet
        // process-wide override caused excessive scheduler handoffs during the
        // startup PM4 burst.
        SetDefault("SHARPEMU_AGC_GATE_QUANTUM_PACKETS", "32");
        SetDefault("SHARPEMU_AGC_GATE_QUANTUM_MS", "1");

        // Shader path
        SetDefault("SHARPEMU_SPIRV_PREWARM_MAX", "512");
        SetDefault("SHARPEMU_SPIRV_PREWARM_MB", "128");
        SetDefault("SHARPEMU_SHADER_TRANSLATE_BUDGET_MS", "80");
        SetDefault("SHARPEMU_SHADER_SOFT_FAIL", "1");

        // V76.3.7.4: ownership is decided by BinkGuestOwnedRuntimeV7600.
        // Do not pre-seed guest ownership here: V76.2.5.1 already defines the
        // normal policy as guest-request -> HostMovieBridge -> FFmpeg, while
        // SHARPEMU_BINK_FORCE_GUEST=1 (or ALLOW_HOST_DECODER=0) remains an
        // explicit diagnostic override for the pure guest GPU decoder.
        var forceGuestBink =
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_FORCE_GUEST"),
                "1",
                StringComparison.Ordinal);
        var explicitHostDisable =
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_ALLOW_HOST_DECODER"),
                "0",
                StringComparison.Ordinal);
        if (forceGuestBink || explicitHostDisable)
        {
            SetDefault("SHARPEMU_BINK_ALLOW_HOST_DECODER", "0");
            SetDefault("SHARPEMU_BINK_HYBRID_HOST", "0");
            SetDefault("SHARPEMU_BINK_DS_HOST_BOOT", "0");
            SetDefault("SHARPEMU_BINK_MODE", "guest");
        }

        // V76.3.9.1_WAIT_CRITICAL_PATH
        SetDefault("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");
        // AgcExports explicitly defines owner-drain as a macOS/default or
        // Windows/Linux opt-in path.  Restore that contract here: the V71
        // dedicated worker remains authoritative and exact producer-latched
        // evidence is still consumed by the fast drain.
        SetDefault("SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN", "0");
        SetDefault("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");
        SetDefault("SHARPEMU_AGC_DEDICATED_NONBLOCKING_GATE", "1");
        SetDefault("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");
        SetDefault("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");

        // V76.3.14.8_PRODUCER_CLOSURE_128_BOOT_RECOVERY
        // Preserve the proven 300 ms aged/live planned-producer trigger, but
        // allow an activated exact producer queue to make deeper FIFO progress.
        // V14.7.1 repeatedly exhausted the 48-payload closure while the same
        // waiter/target remained live. No packet is skipped and guest wait
        // values, fences, barriers and hazard semantics are unchanged.
        SetDefault("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "300");
        SetDefault("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_ITEMS", "128");
        SetDefault("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_LIFETIME_MS", "5000");

        // V76.3.9.2_ORDERED_ACTION_COLLAPSE
        SetDefault("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        SetDefault("SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX", "32");
        SetDefault("SHARPEMU_DISABLED_ACQUIRE_NOFLUSH", "1");
        SetDefault("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");

        // V76.3.10_PERSISTENT_GUEST_RESOURCES
        SetDefault("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        SetDefault("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "1024");
        SetDefault("SHARPEMU_DETILE_GENERATION_RESIDENCY", "1");
        SetDefault("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
        SetDefault("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");
        SetDefault("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");
        SetDefault("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");
        SetDefault("SHARPEMU_SAMPLER_IMAGE_ALIAS", "1");

        // V76.3.11_COMPUTE_SUBMIT_GRAPH
        SetDefault("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");
        SetDefault("SHARPEMU_COMPUTE_WRITE_OVERLAP_PAIR_BARRIER", "1");
        SetDefault("SHARPEMU_COMPUTE_RESOURCE_SETUP_COALESCE", "1");
        SetDefault("SHARPEMU_COMPUTE_SHARED_BATCH", "1");
        SetDefault("SHARPEMU_BARRIERED_COMPUTE_BATCH", "0");
        SetDefault("SHARPEMU_BARRIERED_COMPUTE_BATCH_LIMIT", "4");

        // V76.3.14.9_SINGLE_PHYSICAL_QUEUE_BOOT_AB
        // Controlled boot A/B: preserve every logical DCB/ACB queue, FIFO,
        // WAIT_REG_MEM, resource hazard and timeline bookkeeping, but map the
        // logical graphics/compute work back onto one physical VkQueue.
        // This removes only cross-physical-lane handoff/synchronization from
        // the experiment. Set to 1 manually to reproduce the dual-queue side.
        SetDefault("SHARPEMU_DUAL_PHYSICAL_QUEUE", "0");
        SetDefault("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");
        SetDefault("SHARPEMU_QUEUE_SEPARATE_INFLIGHT_BYTES", "1");
        SetDefault("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");

        // V76.3.14_FRAME_16_67MS_CONTRACT
        SetDefault("SHARPEMU_HOST_TARGET_FPS", "60");
        SetDefault("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "1024");
        SetDefault("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        SetDefault("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        SetDefault("SHARPEMU_QUEUE_MAX_INFLIGHT", "16");
        SetDefault("SHARPEMU_QUEUE_LANE_BURST", "4");

        // Target cadence
        SetDefault("SHARPEMU_HOST_TARGET_FPS", "60");

        Console.Error.WriteLine(
            $"[{Marker}] dedicated_drain=1 gate_quantum=32pk/1ms " +
            "spirv_prewarm=512/128MB shader_budget=80ms " +
            $"bink_policy={(forceGuestBink || explicitHostDisable ? "guest-explicit" : "media-runtime-default")}");
        Console.Error.WriteLine("[V76.3.9.1_WAIT_CRITICAL_PATH] watched_write=1 owner_drain=0 monitor_max_ms=4 dedicated_fast=1");
        Console.Error.WriteLine("[V76.3.14.5_BOOT_WAIT_POLICY_RECOVERY] owner_drain=0 dedicated_drain=1 gate_quantum=32pk/1ms submit_evidence=1 fast_only=1 guest_wait_semantics=unchanged");
        Console.Error.WriteLine("[V76.3.14.8_PRODUCER_CLOSURE_128_BOOT_RECOVERY] closure_age_ms=300 payload_budget=128 lifetime_ms=5000 trigger=aged-live-planned-producer same_queue_fifo=1 waits=unchanged");
        Console.Error.WriteLine("[V76.3.9.2_ORDERED_ACTION_COLLAPSE] microbatch=32 disabled_acquire_noflush=1 preserve_payload_batch=1");
        Console.Error.WriteLine("[V76.3.10_PERSISTENT_GUEST_RESOURCES] resident_shader=1024 detile_generation=1 rebar=1 runtime_scalar=8KB sampler_alias=1 donor=v763781");
        Console.Error.WriteLine("[V76.3.11_COMPUTE_SUBMIT_GRAPH] pair2=1 write_overlap_barrier=1 resource_coalesce=1 shared_batch=1 barriered_batch=0");
        Console.Error.WriteLine("[V76.3.12_TRUE_ASYNC_GRAPHICS_COMPUTE] dual_physical=0 boot_ab=v763149 hazard_tracker=range timeline_sync=preserved inflight=12");
        Console.Error.WriteLine("[V76.3.14.9_SINGLE_PHYSICAL_QUEUE_BOOT_AB] physical_vkqueue=single logical_queues=preserved closure128=1 waits=unchanged hazards=unchanged guest_values=unchanged");
        Console.Error.WriteLine("[V76.3.15.0_5FPS_BASELINE_MERGE] source_donor=src-20260820-133228 perf_donor=v763781 pending_items=192 pending_mb=96 burst=4 inflight=16 reserved_ratio=3/8 single_vkqueue=1 closure128=1 waits=4/20 guest_semantics=preserved");
        Console.Error.WriteLine("[V76.3.14_FRAME_16_67MS_CONTRACT] target_fps=60 recovery_envelope=1 max_guest_work=1024 queue_burst=4 inflight=12");
        Console.Error.WriteLine("[V76.3.14.1_THROUGHPUT_RECOVERY_AB] max_guest_work=1024 queue_burst=4 inflight=12 lane_burst=4 barriered_compute_batch=0 preserved=waitfix+microbatch+residency+pair2+dualqueue");
        Console.Error.WriteLine(
            "[V76.3.7.4][BINK_POLICY_RESTORE] " +
            $"force_guest={(forceGuestBink ? 1 : 0)} " +
            $"explicit_host_disable={(explicitHostDisable ? 1 : 0)} " +
            "normal_flow=guest-request->HostMovieBridge->ffmpeg " +
            "host_auto_boot=off");
    }

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(name)))
        {
            Environment.SetEnvironmentVariable(
                name,
                value,
                EnvironmentVariableTarget.Process);
        }
    }
}
