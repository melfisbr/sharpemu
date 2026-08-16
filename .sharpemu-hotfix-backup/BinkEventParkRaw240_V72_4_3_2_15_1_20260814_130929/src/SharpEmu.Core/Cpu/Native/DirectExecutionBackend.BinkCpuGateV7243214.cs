// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Globalization;
using System.Threading;
using SharpEmu.HLE;

namespace SharpEmu.Core.Cpu.Native;

public sealed partial class DirectExecutionBackend
{
    // V72.4.3.2.14 BINK_GUEST_CPU_GATE
    //
    // The V72.4.3.2.13 diagnostic measured ~11.48 host-core equivalents in
    // SharpEmu while nihav-tool itself consumed <0.5 core. The runtime log
    // showed 13 BPE JobWorkerThread guest workers alive during the exclusive
    // host boot movie. Keep those workers progressing, but add a tiny sleep at
    // their HLE import boundaries only while a host movie decoder is active.
    //
    // Main guest threads, ncaPumpThread, BinkAsy threads, the renderer, and the
    // external decoder are not gated.
    private static readonly int V7243214BinkWorkerSleepMs =
        ResolveV7243214BinkWorkerSleepMs();

    private long _v7243214BinkWorkerGateCount;

    private static int ResolveV7243214BinkWorkerSleepMs()
    {
        var raw = Environment.GetEnvironmentVariable(
            "SHARPEMU_BINK_GUEST_WORKER_SLEEP_MS");

        if (int.TryParse(
                raw,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var parsed))
        {
            return Math.Clamp(parsed, 0, 10);
        }

        return 1;
    }

    private void ApplyV7243214BinkGuestWorkerCpuGate()
    {
        if (V7243214BinkWorkerSleepMs <= 0 ||
            !HostMovieExecutionGateV7243214.IsActive ||
            _activeGuestThreadState is not { } thread ||
            !thread.Name.StartsWith(
                "BPE JobWorkerThread",
                StringComparison.Ordinal))
        {
            return;
        }

        Thread.Sleep(V7243214BinkWorkerSleepMs);

        var count = Interlocked.Increment(
            ref _v7243214BinkWorkerGateCount);

        if (count == 1 || (count % 4096) == 0)
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.guest_worker_cpu_gate " +
                $"count={count} " +
                $"sleep_ms={V7243214BinkWorkerSleepMs} " +
                $"thread='{thread.Name}' " +
                $"active_sessions={HostMovieExecutionGateV7243214.ActiveSessions}");
        }
    }
}
