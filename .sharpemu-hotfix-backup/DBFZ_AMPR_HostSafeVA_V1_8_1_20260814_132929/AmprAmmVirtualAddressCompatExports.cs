// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// DRAGONBALL_AMPR_VA_RANGES_FIX_V1_0

using System;
using SharpEmu.HLE;
using SharpEmu.Libs.Kernel;

namespace SharpEmu.Libs.Ampr;

/// <summary>
/// Compatibility export for the PS5 AMPR/AMM virtual-address layout query.
///
/// Dragon Ball FighterZ calls this very early from the libc initializer.  If the
/// four output values are left untouched, stack/image values are subsequently
/// interpreted as AMM VA ranges and the guest attempts to write into libc text.
/// Keep the PS5 AMM virtual-address layout separate from loaded ELF/PRX images.
/// </summary>
public static class AmprAmmVirtualAddressCompatExports
{
    // General AMM VA: 0x0000000040000000 .. 0x0000008000000000
    private const ulong MemoryVaBase = 0x0000000040000000UL;
    private const ulong MemoryVaSize = 0x0000007FC0000000UL;

    // Frame-buffer VA: 0x0000001000000000 .. 0x0000001004000000
    private const ulong FrameBufferVaBase = 0x0000001000000000UL;
    private const ulong FrameBufferVaSize = 0x0000000004000000UL;

    [SysAbiExport(
        Nid = "wkQR9+xTFKY",
        ExportName = "sceAmprAmmGetVirtualAddressRanges",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int SceAmprAmmGetVirtualAddressRanges(CpuContext ctx)
    {
        var memoryBaseOut = ctx[CpuRegister.Rdi];
        var memorySizeOut = ctx[CpuRegister.Rsi];
        var frameBufferBaseOut = ctx[CpuRegister.Rdx];
        var frameBufferSizeOut = ctx[CpuRegister.Rcx];

        if (memoryBaseOut == 0 ||
            memorySizeOut == 0 ||
            frameBufferBaseOut == 0 ||
            frameBufferSizeOut == 0)
        {
            ctx[CpuRegister.Rax] = unchecked((ulong)(long)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        // The API exposes base + size pairs, not end addresses.  The caller may
        // print [base, base + size] for diagnostics.
        if (!ctx.TryWriteUInt64(memoryBaseOut, MemoryVaBase) ||
            !ctx.TryWriteUInt64(memorySizeOut, MemoryVaSize) ||
            !ctx.TryWriteUInt64(frameBufferBaseOut, FrameBufferVaBase) ||
            !ctx.TryWriteUInt64(frameBufferSizeOut, FrameBufferVaSize))
        {
            ctx[CpuRegister.Rax] = unchecked((ulong)(long)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_LOG_AMPR"),
                "1",
                StringComparison.Ordinal))
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] ampr.amm_get_va_ranges " +
                $"memory=0x{MemoryVaBase:X16}+0x{MemoryVaSize:X16} " +
                $"framebuffer=0x{FrameBufferVaBase:X16}+0x{FrameBufferVaSize:X16}");
        }

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }
}
