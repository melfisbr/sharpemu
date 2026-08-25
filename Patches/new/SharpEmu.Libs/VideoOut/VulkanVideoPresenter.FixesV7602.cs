// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.2: wire host frame pacer into the present path and broaden Bink
// handoff barrier coverage for intro/attract movies.

using SharpEmu.Libs.Media;

namespace SharpEmu.Libs.VideoOut;

internal static unsafe partial class VulkanVideoPresenter
{
    /// <summary>
    /// Call from the present path (immediately before QueuePresent). Safe no-op
    /// when SHARPEMU_HOST_FRAME_PACER=0.
    /// </summary>
    private static void PaceHostPresentV7602()
    {
        _ = HostFramePacerV7602.PaceBeforePresent();
    }

    /// <summary>
    /// Extended movie-name predicate used by the post-logo handoff barrier.
    /// Keeps the original ps_studios_logo.bk2 behaviour and adds attract/intro.
    /// </summary>
    private static bool ShouldArmPostStudiosBarrierV7602(string movieName) =>
        BinkVulkanPacingV7602.ShouldArmHandoffBarrier(movieName);

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void LogFixesV7602()
    {
        Console.Error.WriteLine(
            "[VULKAN][V76.0.2] host_frame_pacer + bink_handoff_expand + spirv_disk_cache ready");
        Console.Error.WriteLine(HostFramePacerV7602.StatusLine());
    }
}
