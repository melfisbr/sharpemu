// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;
using SharpEmu.HLE;

namespace SharpEmu.Core.Cpu.Native;

public sealed partial class DirectExecutionBackend
{
    // V72.4.3.2.15.1 BINK_GUEST_EVENT_PARK
    //
    // V14's Thread.Sleep(1) at HLE import boundaries did not reduce CPU:
    // SharpEmu remained near 11.7 host-core equivalents. Keep the exact same
    // BPE-only scope, but block the reverse-P/Invoke import dispatcher on a
    // kernel-backed event until the last host movie decoder stops.
    //
    // No guest continuation is serialized and no return register is rewritten:
    // execution resumes in the same import call frame after the event releases.
    private long _v72432151BinkWorkerParkCount;
    private long _v72432151BinkWorkerReleaseCount;

    private void ApplyV7243214BinkGuestWorkerCpuGate()
    {
        if (!HostMovieExecutionGateV7243214.IsActive ||
            _activeGuestThreadState is not { } thread ||
            !thread.Name.StartsWith(
                "BPE JobWorkerThread",
                StringComparison.Ordinal))
        {
            return;
        }

        var parkCount = Interlocked.Increment(
            ref _v72432151BinkWorkerParkCount);

        if (parkCount <= 16 || (parkCount % 256) == 0)
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.guest_worker_event_park " +
                $"count={parkCount} " +
                $"thread='{thread.Name}' " +
                $"active_sessions={HostMovieExecutionGateV7243214.ActiveSessions}");
        }

        HostMovieExecutionGateV7243214.WaitUntilInactive();

        var releaseCount = Interlocked.Increment(
            ref _v72432151BinkWorkerReleaseCount);

        if (releaseCount <= 16 || (releaseCount % 256) == 0)
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.guest_worker_event_release " +
                $"count={releaseCount} " +
                $"thread='{thread.Name}' " +
                $"active_sessions={HostMovieExecutionGateV7243214.ActiveSessions}");
        }
    }
}
