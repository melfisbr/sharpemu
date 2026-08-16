// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;

namespace SharpEmu.Libs.Agc;

/// <summary>
/// V55 graphics command sizing completion.
/// Each size is derived from the fixed TryAllocateCommandDwords count of the
/// corresponding already-implemented AGC command emitter in AgcExports.
/// </summary>
public static class AgcGraphicsSizingV55Exports
{
    private static int ReturnSize(CpuContext ctx, uint dwords)
    {
        ctx[CpuRegister.Rax] = dwords * sizeof(uint);
        return (int)ctx[CpuRegister.Rax];
    }

    [SysAbiExport(
        Nid = "PxKWV2fVAps",
        ExportName = "sceAgcAcbDispatchIndirectGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int AcbDispatchIndirectGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 4u);

    [SysAbiExport(
        Nid = "Abendgtz+3o",
        ExportName = "sceAgcCbDispatchGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int CbDispatchGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 5u);

    [SysAbiExport(
        Nid = "w8HVkEeXPv8",
        ExportName = "sceAgcDcbDispatchIndirectGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbDispatchIndirectGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 3u);

    [SysAbiExport(
        Nid = "WrdP9Zxx3lQ",
        ExportName = "sceAgcDcbDrawIndexAutoGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbDrawIndexAutoGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 7u);

    [SysAbiExport(
        Nid = "qMlfB1ZhMDc",
        ExportName = "sceAgcDcbDrawIndexOffsetGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbDrawIndexOffsetGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 5u);

    [SysAbiExport(
        Nid = "cxPZ4Wgvdj8",
        ExportName = "sceAgcDcbDrawIndirectGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbDrawIndirectGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 5u);

    [SysAbiExport(
        Nid = "C4l9fB17t8w",
        ExportName = "sceAgcDcbEventWriteGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbEventWriteGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 2u);

    [SysAbiExport(
        Nid = "j4emHHndCPY",
        ExportName = "sceAgcDcbSetIndexBufferGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbSetIndexBufferGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 5u);

    [SysAbiExport(
        Nid = "ca4KPvp0qLQ",
        ExportName = "sceAgcDcbSetIndexSizeGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbSetIndexSizeGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 2u);

    [SysAbiExport(
        Nid = "6DFuRKT4C9w",
        ExportName = "sceAgcDcbSetNumInstancesGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAgc")]
    public static int DcbSetNumInstancesGetSizeV55(CpuContext ctx) => ReturnSize(ctx, 2u);
}
