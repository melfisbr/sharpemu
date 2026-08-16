// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    // SHARPEMU_LEAF_DISPATCH_HOTPATH_V1_8_9_2
    //
    // This probe executes before the leaf fast path. 2^23 keeps the common
    // case to an integer AND plus branch; no atomics or integer division.
    private static void TraceSparseImportProgressV1892(
        long dispatchIndex,
        string nid)
    {
        const long ProgressMask = (1L << 23) - 1L; // 8,388,608 imports.

        if (dispatchIndex <= 0 || (dispatchIndex & ProgressMask) != 0)
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][TRACE] dbfz.import_progress.v1892 " +
            $"import={dispatchIndex} nid={nid}");
    }
}
