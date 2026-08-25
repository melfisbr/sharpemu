// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.2: adaptive host queue depth, dual-lane fairness, low-latency throttle.

using System.Diagnostics;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// Host-side queue optimizer for graphics/compute/present lanes.
/// Does not reorder guest FIFO; only bounds host backlog and balances
/// how many submissions each lane may push before yielding.
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

    /// <summary>Max in-flight host submits across all lanes (default 3).</summary>
    private static readonly int MaxInFlight =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_QUEUE_MAX_INFLIGHT"),
            out var n)
            ? Math.Clamp(n, 1, 16)
            : 3;

    /// <summary>Per-lane burst before forced yield (default 4).</summary>
    private static readonly int PerLaneBurst =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_QUEUE_LANE_BURST"),
            out var b)
            ? Math.Clamp(b, 1, 32)
            : 4;

    /// <summary>Target frame period for adaptive depth (default 60 Hz).</summary>
    private static readonly double TargetFps =
        double.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_HOST_TARGET_FPS"),
            out var fps)
            ? Math.Clamp(fps, 30.0, 120.0)
            : 60.0;

    private static int _inFlight;
    private static int _graphicsBurst;
    private static int _computeBurst;
    private static long _throttleWaits;
    private static long _graphicsSubmits;
    private static long _computeSubmits;
    private static long _presentSignals;
    private static long _lastFrameTick;
    private static double _emaFrameMs = 16.7;

    internal static long ThrottleWaits => Interlocked.Read(ref _throttleWaits);
    internal static long GraphicsSubmits => Interlocked.Read(ref _graphicsSubmits);
    internal static long ComputeSubmits => Interlocked.Read(ref _computeSubmits);

    /// <summary>
    /// Call before QueueSubmit on the graphics lane.
    /// </summary>
    internal static void BeforeGraphicsSubmit()
    {
        if (!Enabled)
        {
            return;
        }

        WaitForCapacity();
        Interlocked.Increment(ref _graphicsSubmits);
        var burst = Interlocked.Increment(ref _graphicsBurst);
        if (burst >= PerLaneBurst)
        {
            Interlocked.Exchange(ref _graphicsBurst, 0);
            // Yield so compute/present can drain.
            Thread.Sleep(0);
        }
    }

    /// <summary>
    /// Call before QueueSubmit on the async-compute lane.
    /// </summary>
    internal static void BeforeComputeSubmit()
    {
        if (!Enabled)
        {
            return;
        }

        WaitForCapacity();
        Interlocked.Increment(ref _computeSubmits);
        var burst = Interlocked.Increment(ref _computeBurst);
        if (burst >= PerLaneBurst)
        {
            Interlocked.Exchange(ref _computeBurst, 0);
            Thread.Sleep(0);
        }
    }

    /// <summary>
    /// Call when a submit fence/timeline completes (any lane).
    /// </summary>
    internal static void OnSubmitComplete()
    {
        if (!Enabled)
        {
            return;
        }

        var v = Interlocked.Decrement(ref _inFlight);
        if (v < 0)
        {
            Interlocked.Exchange(ref _inFlight, 0);
        }
    }

    /// <summary>
    /// Call at present time — updates frame-time EMA and releases one slot.
    /// </summary>
    internal static void OnPresented()
    {
        if (!Enabled)
        {
            return;
        }

        Interlocked.Increment(ref _presentSignals);
        var now = Stopwatch.GetTimestamp();
        var prev = Interlocked.Exchange(ref _lastFrameTick, now);
        if (prev != 0)
        {
            var ms = (now - prev) * 1000.0 / Stopwatch.Frequency;
            // EMA ~0.2
            var ema = _emaFrameMs;
            ema = ema * 0.8 + ms * 0.2;
            _emaFrameMs = ema;
        }

        OnSubmitComplete();
        Interlocked.Exchange(ref _graphicsBurst, 0);
        Interlocked.Exchange(ref _computeBurst, 0);

        if (Trace)
        {
            var n = Interlocked.Read(ref _presentSignals);
            if (n > 0 && n % 300 == 0)
            {
                Console.Error.WriteLine(
                    $"[QUEUE-OPT][V76.2.2] inflight={Volatile.Read(ref _inFlight)} " +
                    $"max={EffectiveMaxInFlight()} ema_ms={_emaFrameMs:F2} " +
                    $"gfx={GraphicsSubmits} cs={ComputeSubmits} waits={ThrottleWaits}");
            }
        }
    }

    /// <summary>
    /// Adaptive safe queue burst for guest FIFO drain loops.
    /// Faster frames → allow slightly deeper host bursts; slow frames → tighten.
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
            return Math.Min(configuredDefault + 4, 16);
        }

        if (ema >= targetMs * 1.4)
        {
            return Math.Max(2, configuredDefault / 2);
        }

        return configuredDefault;
    }

    private static int EffectiveMaxInFlight()
    {
        var targetMs = 1000.0 / TargetFps;
        var ema = _emaFrameMs;
        if (ema >= targetMs * 1.5)
        {
            return Math.Max(1, MaxInFlight - 1);
        }

        if (ema <= targetMs * 0.85)
        {
            return Math.Min(8, MaxInFlight + 1);
        }

        return MaxInFlight;
    }

    private static void WaitForCapacity()
    {
        var max = EffectiveMaxInFlight();
        var pending = Interlocked.Increment(ref _inFlight);
        if (pending <= max)
        {
            return;
        }

        // Spin briefly then sleep — lower latency than always Sleep(1).
        var spin = 0;
        while (Volatile.Read(ref _inFlight) > max)
        {
            Interlocked.Increment(ref _throttleWaits);
            if (spin++ < 64)
            {
                Thread.SpinWait(64);
            }
            else
            {
                Thread.Sleep(0);
                if (spin > 256)
                {
                    Thread.Sleep(1);
                    spin = 0;
                }
            }

            // Safety: never block forever if completion callbacks are missing.
            if (spin > 0 && Volatile.Read(ref _inFlight) > max + 6)
            {
                Interlocked.Exchange(ref _inFlight, max);
                break;
            }
        }
    }
}
