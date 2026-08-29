// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.4: after PS Studios / Bink close, keep first eboot frames presentable.

using System.Diagnostics;
using SharpEmu.Libs.Media;

namespace SharpEmu.Libs.VideoOut;

internal static class BlackScreenRecoveryV7624
{
    internal const string Marker = "V76.2.4_BLACK_RECOVERY";

    private static long _handoffs;
    private static int _suppressDirectScanoutHoldoffFrames;

    internal static void OnBootMovieClosed(string? moviePath)
    {
        if (!BinkHandoffMoviesV7624.ShouldArm(moviePath) &&
            !IsLogoLike(moviePath))
        {
            return;
        }

        Interlocked.Exchange(ref _suppressDirectScanoutHoldoffFrames, 90);
        var n = Interlocked.Increment(ref _handoffs);
        Console.Error.WriteLine(
            $"[{Marker}] handoff n={n} file='{Path.GetFileName(moviePath ?? "")}' " +
            "direct_scanout_holdoff_frames=90 action=allow-first-guest-frames");
    }

    internal static bool ShouldSkipDirectScanoutSuppress()
    {
        var left = Volatile.Read(ref _suppressDirectScanoutHoldoffFrames);
        if (left <= 0)
        {
            return false;
        }

        Interlocked.Decrement(ref _suppressDirectScanoutHoldoffFrames);
        return true;
    }

    private static bool IsLogoLike(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var name = Path.GetFileName(path);
        return name.Contains("studio", StringComparison.OrdinalIgnoreCase) ||
               name.Contains("logo", StringComparison.OrdinalIgnoreCase) ||
               name.Contains("SIE", StringComparison.OrdinalIgnoreCase);
    }
}
