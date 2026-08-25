// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.5: consolidated present-cadence and frame-time diagnostics.

using System;
using System.Threading;

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanPresentCadenceV7605
{
    private static readonly bool TraceCadence = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_TRACE_PRESENT_CADENCE"),
        "1",
        StringComparison.Ordinal);

    private static readonly bool TraceFrameStats = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_TRACE_FRAME_STATS"),
        "1",
        StringComparison.Ordinal);

    private static long _lastTick;
    private static long _frames;
    private static long _bucket60Plus;
    private static long _bucket30To60;
    private static long _bucketBelow30;
    private static double _emaMs = 16.6667;

    internal static void NoteSuccessfulPresent()
    {
        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        var previous = Interlocked.Exchange(ref _lastTick, now);
        if (previous == 0)
        {
            return;
        }

        var dtMs = (now - previous) * 1000.0 /
            System.Diagnostics.Stopwatch.Frequency;
        var frame = Interlocked.Increment(ref _frames);
        _emaMs = (_emaMs * 0.9) + (dtMs * 0.1);

        if (dtMs <= 16.7)
        {
            Interlocked.Increment(ref _bucket60Plus);
        }
        else if (dtMs <= 33.4)
        {
            Interlocked.Increment(ref _bucket30To60);
        }
        else
        {
            Interlocked.Increment(ref _bucketBelow30);
        }

        if (TraceCadence && (frame <= 8 || frame % 120 == 0))
        {
            var emaFps = _emaMs > 0.001 ? 1000.0 / _emaMs : 0;
            Console.Error.WriteLine(
                $"[PRESENT-CADENCE][V76.0.5] n={frame} dt_ms={dtMs:F3} " +
                $"ema_ms={_emaMs:F3} ema_fps={emaFps:F2}");
        }

        if (TraceFrameStats && frame % 300 == 0)
        {
            var total = Math.Max(1.0, frame);
            Console.Error.WriteLine(
                $"[FRAME-STATS][V76.0.5] n={frame} " +
                $"pct_60plus={100.0 * Interlocked.Read(ref _bucket60Plus) / total:F1}% " +
                $"pct_30_to_60={100.0 * Interlocked.Read(ref _bucket30To60) / total:F1}% " +
                $"pct_below30={100.0 * Interlocked.Read(ref _bucketBelow30) / total:F1}% " +
                $"last_ms={dtMs:F3}");
        }
    }
}
