// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;

namespace SharpEmu.Libs.Kernel;

/// <summary>
/// Positioned resource/file reading required by asset and streaming paths.
/// Uses the existing SharpEmu file-descriptor read/lseek implementation and
/// restores the descriptor position after the read.
/// </summary>
public static class KernelGraphicsResourceIoV55Exports
{
    private const int SeekSet = 0;
    private const int SeekCur = 1;

    [SysAbiExport(
        Nid = "+r3rMFwItV4",
        ExportName = "sceKernelPread",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelPreadV55(CpuContext ctx)
    {
        var fd = unchecked((int)ctx[CpuRegister.Rdi]);
        var buffer = ctx[CpuRegister.Rsi];
        var requested = (int)Math.Min(ctx[CpuRegister.Rdx], int.MaxValue);
        var offset = unchecked((long)ctx[CpuRegister.Rcx]);

        // V59: true positioned I/O. RandomAccess.Read uses the file handle and
        // explicit offset, so sceKernelPread never mutates the shared fd cursor.
        return KernelMemoryCompatExports.KernelPreadAtV59(
            ctx,
            fd,
            buffer,
            requested,
            offset);
    }
}
