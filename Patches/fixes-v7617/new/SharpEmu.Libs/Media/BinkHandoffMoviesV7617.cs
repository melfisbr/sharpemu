// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.1.7: expand post-logo handoff barrier to attract/intro/logo family.

namespace SharpEmu.Libs.Media;

internal static class BinkHandoffMoviesV7617
{
    private static readonly HashSet<string> Movies = new(StringComparer.OrdinalIgnoreCase)
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

    internal static bool ShouldArm(string? movieName)
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
        return Movies.Contains(fileName) ||
               fileName.Contains("logo", StringComparison.OrdinalIgnoreCase) ||
               fileName.Contains("attract", StringComparison.OrdinalIgnoreCase);
    }
}
