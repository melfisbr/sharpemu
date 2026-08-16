// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Threading;

namespace SharpEmu.HLE;

/// <summary>
/// V72.4.3.2.14: process-local host-movie activity gate shared by HLE/Core/Libs.
/// The host Bink decoder owns the session count; Core only observes it.
/// </summary>
public static class HostMovieExecutionGateV7243214
{
    private static int _activeSessions;

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

    public static void Begin() =>
        Interlocked.Increment(ref _activeSessions);

    public static void End()
    {
        while (true)
        {
            var current = Volatile.Read(ref _activeSessions);
            if (current <= 0)
            {
                Interlocked.Exchange(ref _activeSessions, 0);
                return;
            }

            if (Interlocked.CompareExchange(
                    ref _activeSessions,
                    current - 1,
                    current) == current)
            {
                return;
            }
        }
    }
}
