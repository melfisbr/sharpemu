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
    // SHARPEMU_DBFZ_AMPR_HOST_SAFE_VA_V1_8_1
    //
    // The PS5-facing nominal AMM base is 0x40000000. SharpEmu's native backend
    // identity-maps guest pointers onto host virtual addresses, so Windows'
    // permanently occupied 0x7FFE0000 KUSER_SHARED_DATA page makes the nominal
    // range impossible to reproduce literally once AMPR grows past that point.
    //
    // DBFZ obtains the base dynamically from sceAmprAmmGetVirtualAddressRanges
    // and stores/propagates it as a 64-bit value. Keep the PS5 size contract
    // unchanged, but shift the Windows compatibility base to the next 2 GiB
    // boundary, entirely above the fixed system page. Non-Windows hosts retain
    // the nominal base.
    private const ulong NominalMemoryVaBase = 0x0000000040000000UL;
    private const ulong WindowsHostSafeMemoryVaBase = 0x0000000080000000UL;
    private const ulong MemoryVaSize = 0x0000007FC0000000UL;

    // Frame-buffer VA: 0x0000001000000000 .. 0x0000001004000000
    private const ulong FrameBufferVaBase = 0x0000001000000000UL;
    private const ulong FrameBufferVaSize = 0x0000000004000000UL;

    private static ulong ResolveMemoryVaBase()
    {
        if (!OperatingSystem.IsWindows())
        {
            return NominalMemoryVaBase;
        }

        // 0x80000000 is the smallest 1 GiB-aligned base above the immutable
        // Windows user shared-data page at 0x7FFE0000. Keeping the relocation
        // minimal avoids introducing a new address-width assumption into the
        // guest AMM allocator.
        return WindowsHostSafeMemoryVaBase;
    }

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

        var memoryVaBase = ResolveMemoryVaBase();

        // The API exposes base + size pairs, not end addresses.  The caller may
        // print [base, base + size] for diagnostics.
        if (!ctx.TryWriteUInt64(memoryBaseOut, memoryVaBase) ||
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
                $"memory=0x{memoryVaBase:X16}+0x{MemoryVaSize:X16} " +
                $"framebuffer=0x{FrameBufferVaBase:X16}+0x{FrameBufferVaSize:X16} " +
                $"host_safe_relocated={(OperatingSystem.IsWindows() && memoryVaBase != NominalMemoryVaBase)}");
        }

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }
}
