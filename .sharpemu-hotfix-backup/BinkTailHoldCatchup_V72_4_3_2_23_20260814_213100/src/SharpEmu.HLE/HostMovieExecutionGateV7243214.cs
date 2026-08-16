// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Runtime.InteropServices;
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

    // V72.4.3.2.22 HOST_MOVIE_PROCESS_AFFINITY
    // Host Bink decoding runs in a separate nihav-tool process. Limiting only
    // the SharpEmu process during movies prevents the guest BPE worker storm
    // from consuming the machine while leaving the external decoder free.
    private static readonly object AffinitySync = new();
    private static nuint _savedProcessAffinityMask;
    private static int _affinityLimited;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetProcessAffinityMask(
        nint hProcess,
        out nuint lpProcessAffinityMask,
        out nuint lpSystemAffinityMask);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetProcessAffinityMask(
        nint hProcess,
        nuint dwProcessAffinityMask);

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
            TryLimitV7243222ProcessAffinity();
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
                RestoreV7243222ProcessAffinity();
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
                RestoreV7243222ProcessAffinity();
                InactiveEvent.Set();
            }

            return;
        }
    }


    private static void TryLimitV7243222ProcessAffinity()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var configured = 4;
        var raw = Environment.GetEnvironmentVariable(
            "SHARPEMU_BINK_HOST_CPU_LOGICAL");

        if (int.TryParse(raw, out var parsed))
        {
            if (parsed <= 0)
            {
                return;
            }

            configured = Math.Clamp(parsed, 1, 64);
        }

        lock (AffinitySync)
        {
            if (Volatile.Read(ref _affinityLimited) != 0)
            {
                return;
            }

            var process = GetCurrentProcess();
            if (!GetProcessAffinityMask(
                    process,
                    out var processMask,
                    out _))
            {
                return;
            }

            nuint limitedMask = 0;
            var selected = 0;
            var bits = IntPtr.Size * 8;

            for (var bit = 0; bit < bits && selected < configured; bit++)
            {
                var candidate = (nuint)1 << bit;
                if ((processMask & candidate) == 0)
                {
                    continue;
                }

                limitedMask |= candidate;
                selected++;
            }

            if (limitedMask == 0 ||
                limitedMask == processMask)
            {
                return;
            }

            if (!SetProcessAffinityMask(process, limitedMask))
            {
                return;
            }

            _savedProcessAffinityMask = processMask;
            Volatile.Write(ref _affinityLimited, 1);

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.host_cpu_affinity_limit " +
                $"logical={selected} mask=0x{limitedMask:X}");
        }
    }

    private static void RestoreV7243222ProcessAffinity()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        lock (AffinitySync)
        {
            if (Interlocked.Exchange(ref _affinityLimited, 0) == 0)
            {
                return;
            }

            var saved = _savedProcessAffinityMask;
            _savedProcessAffinityMask = 0;

            if (saved == 0)
            {
                return;
            }

            var process = GetCurrentProcess();
            if (SetProcessAffinityMask(process, saved))
            {
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.host_cpu_affinity_restore " +
                    $"mask=0x{saved:X}");
            }
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
