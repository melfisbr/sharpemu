// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.4: helpers for wait-path diagnostics and soft caps.

using System.Diagnostics;

namespace SharpEmu.Libs.Agc;

internal static class GpuWaitFastPathV7624
{
    private static readonly double SoftCapMs =
        double.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_WAIT_SOFT_CAP_MS"),
            out var ms)
            ? Math.Clamp(ms, 5.0, 5000.0)
            : 50.0;

    private static long _overCap;
    private static long _latchedHints;

    internal static double SoftCapMilliseconds => SoftCapMs;

    internal static bool IsOverSoftCap(long registeredTicks)
    {
        if (registeredTicks == 0)
        {
            return false;
        }

        var waited = (Stopwatch.GetTimestamp() - registeredTicks) *
            1000.0 / Stopwatch.Frequency;
        if (waited < SoftCapMs)
        {
            return false;
        }

        Interlocked.Increment(ref _overCap);
        return true;
    }

    internal static void NoteLatchedHint()
    {
        var n = Interlocked.Increment(ref _latchedHints);
        if (n <= 16 || (n & (n - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[WAIT-FAST][V76.2.4] latched_hints={n} soft_cap_ms={SoftCapMs:F0}");
        }
    }
}
