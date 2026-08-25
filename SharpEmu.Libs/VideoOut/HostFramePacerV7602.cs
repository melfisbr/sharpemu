// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.2: host-side frame pacer targeting a steady 60 Hz present cadence.
// Complements guest PaceFlip / Bink wall-clock sessions without replacing them.

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// Lightweight host frame pacer. Sleeps only the residual time to the next
/// target present tick so the swapchain is not over-submitted (which collapses
/// MAILBOX/FIFO into effective 30/20 Hz under load).
/// </summary>
internal static class HostFramePacerV7602
{
    private static readonly bool Enabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_HOST_FRAME_PACER"),
            "0",
            StringComparison.Ordinal);

    private static readonly double TargetFps =
        double.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_HOST_TARGET_FPS"),
            out var fps)
            ? Math.Clamp(fps, 30.0, 120.0)
            : 60.0;

    private static readonly long PeriodTicks =
        (long)(System.Diagnostics.Stopwatch.Frequency / TargetFps);

    private static long _nextPresentTick;
    private static long _pacedFrames;
    private static long _skippedSleeps;

    public static double ConfiguredFps => TargetFps;
    public static long PacedFrames => Interlocked.Read(ref _pacedFrames);
    public static long SkippedSleeps => Interlocked.Read(ref _skippedSleeps);

    /// <summary>
    /// Call immediately before vkQueuePresentKHR (or the host present path).
    /// Returns the number of milliseconds slept (0 if late / disabled).
    /// </summary>
    public static double PaceBeforePresent()
    {
        if (!Enabled || PeriodTicks <= 0)
        {
            return 0;
        }

        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        var next = Interlocked.Read(ref _nextPresentTick);

        if (next == 0 || now > next + PeriodTicks * 2)
        {
            // First frame or we fell more than 2 periods behind: resync.
            Interlocked.Exchange(ref _nextPresentTick, now + PeriodTicks);
            Interlocked.Increment(ref _pacedFrames);
            return 0;
        }

        if (now < next)
        {
            var remainTicks = next - now;
            var remainMs = remainTicks * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
            if (remainMs >= 1.0)
            {
                // Sleep most of the residual; spin the last ~0.3 ms for precision.
                var sleepMs = Math.Max(0, (int)(remainMs - 0.3));
                if (sleepMs > 0)
                {
                    Thread.Sleep(sleepMs);
                }

                while (System.Diagnostics.Stopwatch.GetTimestamp() < next)
                {
                    Thread.SpinWait(32);
                }
            }

            Interlocked.Exchange(ref _nextPresentTick, next + PeriodTicks);
            Interlocked.Increment(ref _pacedFrames);
            return remainMs;
        }

        // Late: do not sleep; advance schedule by one period from now.
        Interlocked.Exchange(ref _nextPresentTick, now + PeriodTicks);
        Interlocked.Increment(ref _skippedSleeps);
        Interlocked.Increment(ref _pacedFrames);
        return 0;
    }

    public static string StatusLine() =>
        $"[FRAME-PACER][V76.0.2] enabled={(Enabled ? 1 : 0)} target_fps={TargetFps:F1} " +
        $"paced={PacedFrames} late={SkippedSleeps}";
}
