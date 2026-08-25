// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.4: rolling frame-time histogram for 60 fps validation.

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanFrameStatsV7604
{
    private static readonly bool Enabled =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_TRACE_FRAME_STATS"),
            "1",
            StringComparison.Ordinal);

    private static long _frames;
    private static long _under16ms;
    private static long _under33ms;
    private static long _over33ms;
    private static long _lastTick;

    internal static void NoteFrameEnd()
    {
        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        var prev = Interlocked.Exchange(ref _lastTick, now);
        if (prev == 0)
        {
            return;
        }

        var ms = (now - prev) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
        Interlocked.Increment(ref _frames);
        if (ms <= 16.7)
        {
            Interlocked.Increment(ref _under16ms);
        }
        else if (ms <= 33.4)
        {
            Interlocked.Increment(ref _under33ms);
        }
        else
        {
            Interlocked.Increment(ref _over33ms);
        }

        var n = Interlocked.Read(ref _frames);
        if (Enabled && n > 0 && n % 300 == 0)
        {
            var total = Math.Max(1.0, n);
            Console.Error.WriteLine(
                $"[FRAME-STATS][V76.0.4] n={n} " +
                $"pct_60fps={100.0 * _under16ms / total:F1}% " +
                $"pct_30fps={100.0 * _under33ms / total:F1}% " +
                $"pct_below_30={100.0 * _over33ms / total:F1}% last_ms={ms:F2}");
        }
    }
}
