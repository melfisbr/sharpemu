// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.2: default Bink pacing to 60 fps on the Vulkan present path and
// expand the set of intro/attract movies that arm the post-logo handoff barrier.

using System.Collections.Concurrent;

namespace SharpEmu.Libs.Media;

internal static class BinkVulkanPacingV7602
{
    internal const string Marker = "V76.0.2_BINK_VULKAN_60FPS";

    /// <summary>
    /// Movies that should keep the black handoff visible until a post-movie
    /// guest flip depends on real work (prevents SIE logo / attract flashback).
    /// </summary>
    private static readonly HashSet<string> HandoffBarrierMovies =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "ps_studios_logo.bk2",
            "playstation_studios_logo.bk2",
            "SIE_logo.bk2",
            "attract.bk2",
            "attract_movie.bk2",
            "intro.bk2",
            "opening.bk2",
            "boot_movie.bk2",
            "logo.bk2",
        };

    private static readonly ConcurrentDictionary<string, byte> Observed =
        new(StringComparer.OrdinalIgnoreCase);

    internal static bool ShouldArmHandoffBarrier(string? movieName)
    {
        if (string.IsNullOrWhiteSpace(movieName))
        {
            return false;
        }

        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_POST_STUDIOS_FRESH_FRAME_BARRIER"),
                "0",
                StringComparison.Ordinal))
        {
            return false;
        }

        var fileName = Path.GetFileName(movieName);
        var arm = HandoffBarrierMovies.Contains(fileName) ||
                  fileName.Contains("logo", StringComparison.OrdinalIgnoreCase) ||
                  fileName.Contains("attract", StringComparison.OrdinalIgnoreCase);

        if (arm)
        {
            Observed.TryAdd(fileName, 0);
        }

        return arm;
    }

    /// <summary>
    /// Preferred Bink target FPS when SHARPEMU_BINK_TARGET_FPS is unset.
    /// </summary>
    internal static int DefaultTargetFps => 60;

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Initialize()
    {
        Console.Error.WriteLine(
            $"[BINK-VULKAN][{Marker}] default_target_fps={DefaultTargetFps} " +
            $"handoff_movies={HandoffBarrierMovies.Count}");
    }
}
