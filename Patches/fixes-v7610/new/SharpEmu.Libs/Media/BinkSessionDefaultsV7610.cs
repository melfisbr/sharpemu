// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.10: prefer wall-clock Bink sessions at 60 fps unless explicitly disabled.

namespace SharpEmu.Libs.Media;

internal static class BinkSessionDefaultsV7610
{
    internal const string Marker = "V76.0.10_BINK_SESSION_60";

    /// <summary>
    /// When SHARPEMU_BINK_WALLCLOCK_SESSION is unset, treat as enabled so
    /// movie timing tracks host clock at the configured target FPS.
    /// </summary>
    internal static bool PreferWallClockSession =>
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_WALLCLOCK_SESSION"),
            "0",
            StringComparison.Ordinal);

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Initialize()
    {
        Console.Error.WriteLine(
            $"[BINK][{Marker}] prefer_wallclock={(PreferWallClockSession ? 1 : 0)} " +
            "(set SHARPEMU_BINK_WALLCLOCK_SESSION=0 to disable)");
    }
}
