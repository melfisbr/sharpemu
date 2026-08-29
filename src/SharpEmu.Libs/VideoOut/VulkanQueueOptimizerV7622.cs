// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.2/V76.0.26: fence-paired, non-blocking queue telemetry/fairness hooks.

using System.Diagnostics;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// Host queue accounting for graphics/compute/present lanes. V76.0.26 removes
/// the old pre-submit capacity wait: presenter fence retirement runs on the same
/// host thread, so blocking before QueueSubmit could prevent the code that frees
/// capacity from ever running. The existing presenter submission-capacity logic
/// remains the only backlog gate; these hooks now account successful submits and
/// real fence completions without changing guest FIFO order.
/// </summary>
internal static class VulkanQueueOptimizerV7622
{
    private static readonly bool Enabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_QUEUE_OPTIMIZER"),
            "0",
            StringComparison.Ordinal);

    private static readonly bool Trace =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_TRACE_QUEUE_OPTIMIZER"),
            "1",
            StringComparison.Ordinal);

    private static readonly int MaxInFlight =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_QUEUE_MAX_INFLIGHT"),
            out var n)
            ? Math.Clamp(n, 1, 64)
            : 16;

    private static readonly int PerLaneBurst =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_QUEUE_LANE_BURST"),
            out var b)
            ? Math.Clamp(b, 1, 64)
            : 8;

    private static readonly double TargetFps =
        double.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_HOST_TARGET_FPS"),
            out var fps)
            ? Math.Clamp(fps, 15.0, 240.0)
            : 60.0;

    private static int _inFlight;
    private static int _graphicsBurst;
    private static int _computeBurst;
    private static long _overTargetSamples;
    private static long _graphicsSubmits;
    private static long _computeSubmits;
    private static long _presentSignals;
    private static long _completionSignals;
    private static long _lastFrameTick;
    private static double _emaFrameMs = 16.7;

    internal static long ThrottleWaits => Interlocked.Read(ref _overTargetSamples);
    internal static long GraphicsSubmits => Interlocked.Read(ref _graphicsSubmits);
    internal static long ComputeSubmits => Interlocked.Read(ref _computeSubmits);
    internal static double TargetFrameMilliseconds => 1000.0 / TargetFps;
    internal static double EmaFrameMilliseconds => Volatile.Read(ref _emaFrameMs);

    internal static void OnGraphicsSubmitted() => OnSubmitted(computeLane: false);

    internal static void OnComputeSubmitted() => OnSubmitted(computeLane: true);

    internal static void OnSubmitComplete()
    {
        if (!Enabled)
        {
            return;
        }

        Interlocked.Increment(ref _completionSignals);
        var value = Interlocked.Decrement(ref _inFlight);
        if (value < 0)
        {
            // Completion must never turn accounting into a negative backlog.
            Interlocked.Exchange(ref _inFlight, 0);
        }
    }

    internal static void OnPresented()
    {
        if (!Enabled)
        {
            return;
        }

        Interlocked.Increment(ref _presentSignals);
        var now = Stopwatch.GetTimestamp();
        var previous = Interlocked.Exchange(ref _lastFrameTick, now);
        if (previous != 0)
        {
            var ms = (now - previous) * 1000.0 / Stopwatch.Frequency;
            _emaFrameMs = _emaFrameMs * 0.8 + ms * 0.2;
        }

        // Present is not a submit completion. Fence retirement owns _inFlight.
        Interlocked.Exchange(ref _graphicsBurst, 0);
        Interlocked.Exchange(ref _computeBurst, 0);

        if (Trace)
        {
            var count = Interlocked.Read(ref _presentSignals);
            if (count <= 8 || count % 300 == 0)
            {
                Console.Error.WriteLine(
                    $"[QUEUE-OPT][V76.0.26] inflight={Volatile.Read(ref _inFlight)} " +
                    $"target={EffectiveMaxInFlight()} ema_ms={_emaFrameMs:F2} " +
                    $"budget_ms={TargetFrameMilliseconds:F3} " +
                    $"gfx={GraphicsSubmits} cs={ComputeSubmits} " +
                    $"complete={Interlocked.Read(ref _completionSignals)} " +
                    $"over_target={ThrottleWaits}");
            }
        }
    }

    /// <summary>
    /// Retained as an advisory helper for future scheduler work. V76.0.26 does
    /// not connect it to the presenter's much larger guest-work drain budget.
    /// </summary>
    internal static int RecommendedGuestBurst(int configuredDefault)
    {
        if (!Enabled)
        {
            return configuredDefault;
        }

        var targetMs = 1000.0 / TargetFps;
        var ema = _emaFrameMs;
        if (ema <= targetMs * 0.9)
        {
            return Math.Min(configuredDefault + 4, 64);
        }
        if (ema >= targetMs * 1.4)
        {
            return Math.Max(2, configuredDefault / 2);
        }
        return configuredDefault;
    }

    private static void OnSubmitted(bool computeLane)
    {
        if (!Enabled)
        {
            return;
        }

        if (computeLane)
        {
            Interlocked.Increment(ref _computeSubmits);
            if (Interlocked.Increment(ref _computeBurst) >= PerLaneBurst)
            {
                Interlocked.Exchange(ref _computeBurst, 0);
                Thread.Yield();
            }
        }
        else
        {
            Interlocked.Increment(ref _graphicsSubmits);
            if (Interlocked.Increment(ref _graphicsBurst) >= PerLaneBurst)
            {
                Interlocked.Exchange(ref _graphicsBurst, 0);
                Thread.Yield();
            }
        }

        var pending = Interlocked.Increment(ref _inFlight);
        if (pending > EffectiveMaxInFlight())
        {
            // Telemetry only. Never wait here: fence retirement is presenter-driven.
            Interlocked.Increment(ref _overTargetSamples);
        }
    }

    private static int EffectiveMaxInFlight()
    {
        var targetMs = 1000.0 / TargetFps;
        var ema = _emaFrameMs;
        if (ema >= targetMs * 1.5)
        {
            return Math.Max(2, MaxInFlight - 2);
        }
        if (ema <= targetMs * 0.85)
        {
            return Math.Min(64, MaxInFlight + 4);
        }
        return MaxInFlight;
    }
}
