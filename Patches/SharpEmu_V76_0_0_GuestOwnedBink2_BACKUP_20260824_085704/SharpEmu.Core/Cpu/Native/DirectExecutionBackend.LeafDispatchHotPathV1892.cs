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
    private void TraceSparseImportProgressV1892(
        long dispatchIndex,
        string nid)
    {
        // SHARPEMU_V74_0_101_DBFZ_IMPORT_PROGRESS_DEFENSE
        // The sparse-mask test lives at the callsite. Keep a defensive title
        // guard here so no future direct caller can arm DBFZ probes cross-title.
        if (!SharpEmu.Libs.Kernel.KernelMemoryCompatExports
                .IsConfiguredApplicationTitle("PPSA09790"))
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][TRACE] dbfz.import_progress.v1892 " +
            $"import={dispatchIndex} nid={nid}");

        MaybeStartPostFaprStallProbeV1810(dispatchIndex);
    }
}
