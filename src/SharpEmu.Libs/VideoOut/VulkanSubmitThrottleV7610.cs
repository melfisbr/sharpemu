// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.10: light back-pressure when the host present queue is more than
// ~2 frames ahead of the swapchain, reducing stutter that collapses 60→30.

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanSubmitThrottleV7610
{
    private static readonly bool Enabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_SUBMIT_THROTTLE"),
            "0",
            StringComparison.Ordinal);

    private static readonly int MaxPendingFrames =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_SUBMIT_THROTTLE_FRAMES"),
            out var frames)
            ? Math.Clamp(frames, 1, 8)
            : 2;

    private static int _pending;
    private static long _throttleSleeps;

    internal static long ThrottleSleeps => Interlocked.Read(ref _throttleSleeps);

    internal static void OnSubmitQueued()
    {
        if (!Enabled)
        {
            return;
        }

        var pending = Interlocked.Increment(ref _pending);
        while (pending > MaxPendingFrames)
        {
            Thread.Sleep(1);
            Interlocked.Increment(ref _throttleSleeps);
            pending = Volatile.Read(ref _pending);
            if (pending <= MaxPendingFrames)
            {
                break;
            }

            // Avoid infinite spin if presents never complete (caller must OnPresented).
            if (pending > MaxPendingFrames + 4)
            {
                Interlocked.Exchange(ref _pending, MaxPendingFrames);
                break;
            }
        }
    }

    internal static void OnPresented()
    {
        if (!Enabled)
        {
            return;
        }

        var v = Interlocked.Decrement(ref _pending);
        if (v < 0)
        {
            Interlocked.Exchange(ref _pending, 0);
        }
    }
}
