// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Threading;

namespace SharpEmu.HLE;

/// <summary>
/// V72.4.3.2.14: process-local host-movie activity gate shared by HLE/Core/Libs.
/// V72.4.3.2.15.1 upgrades the gate from polling/sleep to an event wait.
/// </summary>
public static class HostMovieExecutionGateV7243214
{
    private static int _activeSessions;

    // V72.4.3.2.15.1 BINK_GUEST_EVENT_PARK
    // spinCount=0 avoids burning CPU before falling back to the kernel wait.
    private static readonly ManualResetEventSlim InactiveEvent =
        new(initialState: true, spinCount: 0);

    public static bool IsActive =>
        Volatile.Read(ref _activeSessions) > 0;

    public static int ActiveSessions
    {
        get
        {
            var value = Volatile.Read(ref _activeSessions);
            return value > 0 ? value : 0;
        }
    }

    public static void Begin()
    {
        var count = Interlocked.Increment(ref _activeSessions);
        if (count == 1)
        {
            InactiveEvent.Reset();
        }
    }

    public static void End()
    {
        while (true)
        {
            var current = Volatile.Read(ref _activeSessions);
            if (current <= 0)
            {
                Interlocked.Exchange(ref _activeSessions, 0);
                InactiveEvent.Set();
                return;
            }

            var next = current - 1;
            if (Interlocked.CompareExchange(
                    ref _activeSessions,
                    next,
                    current) != current)
            {
                continue;
            }

            if (next == 0)
            {
                InactiveEvent.Set();
            }

            return;
        }
    }

    /// <summary>
    /// Parks a host thread without polling while a host movie is active.
    /// The timeout is only a teardown safety valve; it does not release the
    /// caller while ActiveSessions is still non-zero.
    /// </summary>
    public static void WaitUntilInactive()
    {
        while (Volatile.Read(ref _activeSessions) > 0)
        {
            _ = InactiveEvent.Wait(1000);
        }
    }
}
