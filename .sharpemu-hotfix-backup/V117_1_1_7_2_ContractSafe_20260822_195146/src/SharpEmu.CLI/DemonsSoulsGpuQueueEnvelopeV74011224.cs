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
