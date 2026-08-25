// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.3: lightweight present cadence diagnostics for 60 fps tuning.

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanPresentDiagnosticsV7603
{
    private static readonly bool Enabled =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_TRACE_PRESENT_CADENCE"),
            "1",
            StringComparison.Ordinal);

    private static long _lastPresentTick;
    private static long _presentCount;
    private static double _emaMs = 16.67;

    internal static void NotePresent()
    {
        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        var prev = Interlocked.Exchange(ref _lastPresentTick, now);
        var n = Interlocked.Increment(ref _presentCount);
        if (prev == 0)
        {
            return;
        }

        var dtMs = (now - prev) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
        _emaMs = (_emaMs * 0.9) + (dtMs * 0.1);

        if (Enabled && (n <= 5 || n % 120 == 0))
        {
            var fps = _emaMs > 0.1 ? 1000.0 / _emaMs : 0;
            Console.Error.WriteLine(
                $"[PRESENT][V76.0.3] n={n} dt_ms={dtMs:F2} ema_ms={_emaMs:F2} ema_fps={fps:F1}");
        }
    }
}
