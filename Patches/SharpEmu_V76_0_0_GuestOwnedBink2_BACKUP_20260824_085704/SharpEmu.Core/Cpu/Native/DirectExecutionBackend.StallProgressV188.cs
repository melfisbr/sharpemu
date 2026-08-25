// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    // SHARPEMU_DBFZ_STALL_PROGRESS_V1_8_8
    //
    // One progress line per ten million imports is intentionally sparse enough
    // to avoid turning diagnostics back into a hot-path bottleneck.
    private static long _dbfzLastProgressBucketV188 = -1;

    private static void TraceSparseImportProgressV188(
        long dispatchIndex,
        string nid,
        ulong returnRip)
    {
        var bucket = dispatchIndex / 10_000_000L;
        if (bucket <= 0 ||
            Interlocked.Exchange(ref _dbfzLastProgressBucketV188, bucket) == bucket)
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][TRACE] dbfz.import_progress.v188 " +
            $"import={dispatchIndex} nid={nid} ret=0x{returnRip:X16}");
    }
}
