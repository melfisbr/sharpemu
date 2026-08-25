// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.3: stronger catch-up defaults so Bink can hold 60 fps after stalls.

namespace SharpEmu.Libs.Media;

internal static class BinkCatchupV7603
{
    internal const string Marker = "V76.0.3_BINK_CATCHUP_60";

    /// <summary>Recommended max catch-up frames when env is unset (was 8).</summary>
    internal static int DefaultCatchupMaxFrames => 12;

    /// <summary>Recommended catch-up budget ms when env is unset (was 6).</summary>
    internal static int DefaultCatchupBudgetMs => 10;

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Initialize()
    {
        Console.Error.WriteLine(
            $"[BINK][{Marker}] suggest SHARPEMU_BINK_CATCHUP_MAX_FRAMES={DefaultCatchupMaxFrames} " +
            $"SHARPEMU_BINK_CATCHUP_BUDGET_MS={DefaultCatchupBudgetMs}");
    }
}
