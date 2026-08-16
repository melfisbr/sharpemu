// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Diagnostics;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    // SHARPEMU_DBFZ_POST_FAPR_STALL_SNAPSHOT_V1_8_10
    //
    // V1.8.9.2 proved exact import progress through 67,108,864, followed by
    // FAPREventQueueListener creation and then no further 8,388,608-import
    // checkpoint for the remainder of the 240-second diagnostic.
    //
    // This monitor starts only at/after the 2^26 checkpoint. It observes the
    // existing exact block counter (_importDispatchCount changes every 256
    // imports) from a background thread. No guest state is modified.
    private int _postFaprStallProbeStartedV1810;

    private void MaybeStartPostFaprStallProbeV1810(long dispatchIndex)
    {
        const long StartThreshold = 1L << 26; // 67,108,864 imports.

        if (dispatchIndex < StartThreshold ||
            Interlocked.CompareExchange(
                ref _postFaprStallProbeStartedV1810,
                1,
                0) != 0)
        {
            return;
        }

        var monitor = new Thread(() =>
        {
            const int PollMilliseconds = 1000;
            const int StallSeconds = 12;
            const int RecheckMilliseconds = 5000;

            var lastCount = Volatile.Read(ref _importDispatchCount);
            var stableSince = Stopwatch.GetTimestamp();
            var stallTicks = (long)(StallSeconds * (double)Stopwatch.Frequency);

            Console.Error.WriteLine(
                $"[LOADER][TRACE] dbfz.post_fapr_probe.v1810 armed " +
                $"checkpoint={dispatchIndex} counter={lastCount}");

            while (!_stallWatchdogStop)
            {
                Thread.Sleep(PollMilliseconds);

                var currentCount = Volatile.Read(ref _importDispatchCount);
                if (currentCount != lastCount)
                {
                    lastCount = currentCount;
                    stableSince = Stopwatch.GetTimestamp();
                    continue;
                }

                if (Stopwatch.GetTimestamp() - stableSince < stallTicks)
                {
                    continue;
                }

                Console.Error.WriteLine(
                    $"[LOADER][ERROR] dbfz.post_fapr_stall.v1810 " +
                    $"no_import_progress_seconds={StallSeconds} " +
                    $"counter={currentCount}");

                // Existing non-mutating diagnostic: CPU context, import stub,
                // stack, entry host context and up to 48 guest-thread states.
                LogStallWatchdogSnapshot();
                Console.Error.Flush();

                Thread.Sleep(RecheckMilliseconds);

                var recheckCount = Volatile.Read(ref _importDispatchCount);
                if (recheckCount == currentCount)
                {
                    Console.Error.WriteLine(
                        $"[LOADER][ERROR] dbfz.post_fapr_stall_recheck.v1810 " +
                        $"counter={recheckCount} additional_ms={RecheckMilliseconds}");
                    LogStallWatchdogSnapshot();
                    Console.Error.Flush();
                }
                else
                {
                    Console.Error.WriteLine(
                        $"[LOADER][TRACE] dbfz.post_fapr_stall_resumed.v1810 " +
                        $"before={currentCount} after={recheckCount}");
                }

                return;
            }
        })
        {
            IsBackground = true,
            Name = "SharpEmu-DBFZ-PostFAPRProbe"
        };

        monitor.Start();
    }
}
