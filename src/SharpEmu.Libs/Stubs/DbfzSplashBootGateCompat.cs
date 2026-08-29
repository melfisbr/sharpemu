// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;
using SharpEmu.HLE;
using SharpEmu.Libs.Kernel;

namespace SharpEmu.Libs.Stubs;

/// <summary>
/// Title-scoped startup compatibility for Dragon Ball FighterZ
/// (PPSA09790 / 01.000.010).
///
/// Runtime evidence shows the title reaches its Unreal async/network startup,
/// then encounters two still-unresolved PS5 imports immediately before it
/// settles into a timeout-only splash-screen loop.  Their public symbol names
/// are not present in the available NID catalogue, so this compatibility layer
/// binds the exact NIDs observed from the guest instead of guessing an ABI.
///
/// The handlers deliberately do not write guest memory.  They only replace the
/// generic ORBIS_GEN2_ERROR_NOT_FOUND result with ORBIS_GEN2_OK for this title,
/// which is the narrowest safe way to let optional Pad/SharePlay startup probes
/// continue.  Other titles retain the original NOT_FOUND behavior.
/// </summary>
public static class DbfzSplashBootGateCompat
{
    private const string TitleId = "PPSA09790";
    private const string DisableEnvironmentVariable = "SHARPEMU_DBFZ_SPLASH_BOOT_GATE_COMPAT";

    private static int _padCompatCalls;
    private static int _sharePlayCompatCalls;

    private static int SetReturn(CpuContext ctx, OrbisGen2Result result)
    {
        var value = (int)result;
        ctx[CpuRegister.Rax] = unchecked((ulong)(long)value);
        return value;
    }

    private static bool IsEnabledForDbfz()
    {
        if (!KernelMemoryCompatExports.IsConfiguredApplicationTitle(TitleId))
        {
            return false;
        }

        return !string.Equals(
            Environment.GetEnvironmentVariable(DisableEnvironmentVariable),
            "0",
            StringComparison.Ordinal);
    }

    private static int ReturnDbfzStartupSuccess(
        CpuContext ctx,
        string service,
        string nid,
        ref int counter)
    {
        if (!IsEnabledForDbfz())
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        var call = Interlocked.Increment(ref counter);
        if (call <= 4 || (call & (call - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[DBFZ-BOOT-GATE][V76.3.2] service={service} nid={nid} " +
                $"call={call} action=optional-probe-success memory_write=0 title={TitleId}");
        }

        return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
    }

#pragma warning disable SHEM006 // Exact runtime NIDs; public names are not in the available PS5 symbol catalogue.
    [SysAbiExport(
        Nid = "n3kSX62fgNo",
        ExportName = "sceUnknownDbfzPadN3kSX62fgNo",
        Target = Generation.Gen5,
        LibraryName = "libScePad")]
    public static int DbfzPadStartupProbe(CpuContext ctx) =>
        ReturnDbfzStartupSuccess(
            ctx,
            "libScePad",
            "n3kSX62fgNo",
            ref _padCompatCalls);

    [SysAbiExport(
        Nid = "FzQS6DREDfk",
        ExportName = "sceUnknownDbfzSharePlayFzQS6DREDfk",
        Target = Generation.Gen5,
        LibraryName = "libSceSharePlay")]
    public static int DbfzSharePlayStartupProbe(CpuContext ctx) =>
        ReturnDbfzStartupSuccess(
            ctx,
            "libSceSharePlay",
            "FzQS6DREDfk",
            ref _sharePlayCompatCalls);
#pragma warning restore SHEM006
}
