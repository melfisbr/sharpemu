// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Libs.Media;

internal static class BinkHandoffMoviesV7624
{
    private static readonly string[] Extra =
    {
        "ps_studios_logo.bk2",
        "playstation_studios_logo.bk2",
        "SIE_logo.bk2",
        "SIE.bk2",
        "ps_logo.bk2",
        "sony.bk2",
        "attract.bk2",
        "attract_movie.bk2",
        "intro.bk2",
        "opening.bk2",
        "boot_movie.bk2",
        "logo.bk2",
        "legal.bk2",
        "warning.bk2",
    };

    internal static bool ShouldArm(string? movieName)
    {
        if (BinkHandoffMoviesV7617.ShouldArm(movieName))
        {
            return true;
        }

        if (string.IsNullOrWhiteSpace(movieName))
        {
            return false;
        }

        var file = Path.GetFileName(movieName);
        foreach (var e in Extra)
        {
            if (string.Equals(file, e, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return file.Contains("studio", StringComparison.OrdinalIgnoreCase);
    }
}
