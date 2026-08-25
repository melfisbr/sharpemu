// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;

namespace SharpEmu.Libs.Np;

public static class NpSessionSignalingExports
{
    private const int ErrorInvalidArgument = unchecked((int)0x80552D02);
    private static readonly object Gate = new();
    private static readonly HashSet<int> Contexts = [];
    private static readonly HashSet<int> ActiveContexts = [];
    private static int _nextContext;
    [SysAbiExport(
        Nid = "ysmw6J-P8Ak",
        ExportName = "sceNpSessionSignalingInitialize",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpSessionSignaling")]
    public static int NpSessionSignalingInitialize(CpuContext ctx)
    {
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(Nid = "aBuX0PX-T7I", ExportName = "sceNpSessionSignalingCreateContext2", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpSessionSignaling")]
    public static int NpSessionSignalingCreateContext2(CpuContext ctx)
    {
        var outAddress = ctx[CpuRegister.Rdx] != 0 ? ctx[CpuRegister.Rdx] : ctx[CpuRegister.Rsi];
        if (outAddress == 0) return ctx.SetReturn(ErrorInvalidArgument);
        var id = Interlocked.Increment(ref _nextContext);
        lock (Gate) Contexts.Add(id);
        if (!ctx.TryWriteInt32(outAddress, id)) { lock (Gate) Contexts.Remove(id); return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT); }
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "r4XacqHvkn4", ExportName = "sceNpSessionSignalingActivateSession", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpSessionSignaling")]
    public static int NpSessionSignalingActivateSession(CpuContext ctx)
    {
        var id = unchecked((int)ctx[CpuRegister.Rdi]); lock (Gate) { if (!Contexts.Contains(id)) return ctx.SetReturn(ErrorInvalidArgument); ActiveContexts.Add(id); } return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "cQkBH-pXhF0", ExportName = "sceNpSessionSignalingDeactivate", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpSessionSignaling")]
    public static int NpSessionSignalingDeactivate(CpuContext ctx)
    {
        var id = unchecked((int)ctx[CpuRegister.Rdi]); lock (Gate) { if (!Contexts.Contains(id)) return ctx.SetReturn(ErrorInvalidArgument); ActiveContexts.Remove(id); } return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "Z9Q9LzQDXf0", ExportName = "sceNpSessionSignalingDestroyContext", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpSessionSignaling")]
    public static int NpSessionSignalingDestroyContext(CpuContext ctx)
    {
        var id = unchecked((int)ctx[CpuRegister.Rdi]); lock (Gate) { ActiveContexts.Remove(id); if (!Contexts.Remove(id)) return ctx.SetReturn(ErrorInvalidArgument); } return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "yJw2m6UWDYU", ExportName = "sceNpSessionSignalingGetConnectionInfo", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpSessionSignaling")]
    public static int NpSessionSignalingGetConnectionInfo(CpuContext ctx)
    {
        var id = unchecked((int)ctx[CpuRegister.Rdi]); var output = ctx[CpuRegister.Rdx] != 0 ? ctx[CpuRegister.Rdx] : ctx[CpuRegister.Rsi];
        lock (Gate) if (!Contexts.Contains(id)) return ctx.SetReturn(ErrorInvalidArgument);
        if (output == 0) return ctx.SetReturn(ErrorInvalidArgument);
        Span<byte> info = stackalloc byte[32]; info.Clear(); info[0] = 1;
        return ctx.Memory.TryWrite(output, info) ? ctx.SetReturn(0) : ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
    }

    [SysAbiExport(Nid = "CqJuNXo5yiM", ExportName = "sceNpSessionSignalingTerminate", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpSessionSignaling")]
    public static int NpSessionSignalingTerminate(CpuContext ctx) { lock (Gate) { Contexts.Clear(); ActiveContexts.Clear(); } return ctx.SetReturn(0); }
}
