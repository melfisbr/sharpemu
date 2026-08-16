// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;

namespace SharpEmu.Libs.Kernel;

public static class KernelPthreadV45Aliases
{
    // V45: named scePthread aliases for already-functional POSIX rwlock try paths.

    // V45_EXPORT_BEGIN nid=XD3mDeybCnk
    [SysAbiExport(
        Nid = "XD3mDeybCnk",
        ExportName = "scePthreadRwlockTryrdlock",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int V45KernelAlias01(CpuContext ctx) =>
        KernelPthreadExtendedCompatExports.PosixPthreadRwlockTryrdlock(ctx);
    // V45_EXPORT_END nid=XD3mDeybCnk

    // V45_EXPORT_BEGIN nid=bIHoZCTomsI
    [SysAbiExport(
        Nid = "bIHoZCTomsI",
        ExportName = "scePthreadRwlockTrywrlock",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int V45KernelAlias02(CpuContext ctx) =>
        KernelPthreadExtendedCompatExports.PosixPthreadRwlockTrywrlock(ctx);
    // V45_EXPORT_END nid=bIHoZCTomsI

}
