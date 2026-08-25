// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Np;

public static class NpCppWebApiV45Exports
{
    // V45: deterministic local CppWebApi service-model compatibility batch.
    // Only object lifecycle and primitive property state proven by method-pair ABI
    // are implemented here. Remote service operations and proprietary layouts remain blocked.
    private readonly record struct ObjectKey(ulong Address, int TypeId);

    private sealed class ObjectState
    {
        public object Gate { get; } = new();
        public Dictionary<int, ulong> Fields { get; } = new();
        public ulong LibContext { get; set; }
    }

    private enum ValueSource
    {
        U8Ref,
        U16Ref,
        U32Ref,
        U64Ref,
        Register,
        Xmm32,
        Xmm64,
    }

    private enum ReturnKind
    {
        Bool,
        U32,
        U64,
        Float32,
        Float64,
    }

    private static readonly ConditionalWeakTable<object, ConcurrentDictionary<ObjectKey, ObjectState>> _states = new();

    private static ConcurrentDictionary<ObjectKey, ObjectState> StateMap(CpuContext ctx) =>
        _states.GetValue(ctx.Memory, static _ => new ConcurrentDictionary<ObjectKey, ObjectState>());

    private static ObjectState? TryGetState(CpuContext ctx, ulong address, int typeId)
    {
        if (address == 0)
        {
            return null;
        }

        return StateMap(ctx).TryGetValue(new ObjectKey(address, typeId), out var state)
            ? state
            : null;
    }

    private static ObjectState GetOrCreateState(CpuContext ctx, ulong address, int typeId) =>
        StateMap(ctx).GetOrAdd(new ObjectKey(address, typeId), static _ => new ObjectState());

    private static bool TryReadUnsigned(CpuContext ctx, ulong address, int byteCount, out ulong value)
    {
        value = 0;
        if (address == 0)
        {
            return false;
        }

        Span<byte> bytes = stackalloc byte[8];
        var slice = bytes[..byteCount];
        if (!ctx.Memory.TryRead(address, slice))
        {
            return false;
        }

        value = byteCount switch
        {
            1 => slice[0],
            2 => BinaryPrimitives.ReadUInt16LittleEndian(slice),
            4 => BinaryPrimitives.ReadUInt32LittleEndian(slice),
            8 => BinaryPrimitives.ReadUInt64LittleEndian(slice),
            _ => 0,
        };
        return byteCount is 1 or 2 or 4 or 8;
    }

    private static int Construct(CpuContext ctx, int typeId)
    {
        var address = ctx[CpuRegister.Rdi];
        if (address == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        var state = GetOrCreateState(ctx, address, typeId);
        lock (state.Gate)
        {
            state.Fields.Clear();
            state.LibContext = ctx[CpuRegister.Rsi];
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int Destruct(CpuContext ctx, int typeId)
    {
        var address = ctx[CpuRegister.Rdi];
        if (address != 0)
        {
            StateMap(ctx).TryRemove(new ObjectKey(address, typeId), out _);
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int SetValue(CpuContext ctx, int typeId, int fieldId, ValueSource source, bool normalizeBool)
    {
        var address = ctx[CpuRegister.Rdi];
        if (address == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        ulong raw;
        switch (source)
        {
            case ValueSource.U8Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 1, out raw))
                    return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                break;
            case ValueSource.U16Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 2, out raw))
                    return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                break;
            case ValueSource.U32Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 4, out raw))
                    return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                break;
            case ValueSource.U64Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 8, out raw))
                    return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                break;
            case ValueSource.Register:
                raw = ctx[CpuRegister.Rsi];
                break;
            case ValueSource.Xmm32:
                ctx.GetXmmRegister(0, out raw, out _);
                raw &= uint.MaxValue;
                break;
            case ValueSource.Xmm64:
                ctx.GetXmmRegister(0, out raw, out _);
                break;
            default:
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (normalizeBool)
            raw = raw == 0 ? 0UL : 1UL;

        var state = GetOrCreateState(ctx, address, typeId);
        lock (state.Gate)
            state.Fields[fieldId] = raw;

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int GetValue(CpuContext ctx, int typeId, int fieldId, ReturnKind kind)
    {
        ulong raw = 0;
        var state = TryGetState(ctx, ctx[CpuRegister.Rdi], typeId);
        if (state is not null)
        {
            lock (state.Gate)
                _ = state.Fields.TryGetValue(fieldId, out raw);
        }

        switch (kind)
        {
            case ReturnKind.Bool:
                ctx[CpuRegister.Rax] = raw == 0 ? 0UL : 1UL;
                break;
            case ReturnKind.U32:
                ctx[CpuRegister.Rax] = raw & uint.MaxValue;
                break;
            case ReturnKind.U64:
                ctx[CpuRegister.Rax] = raw;
                break;
            case ReturnKind.Float32:
                ctx.SetXmmRegister(0, raw & uint.MaxValue, 0);
                break;
            case ReturnKind.Float64:
                ctx.SetXmmRegister(0, raw, 0);
                break;
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int IsSet(CpuContext ctx, int typeId, int fieldId)
    {
        var result = false;
        var state = TryGetState(ctx, ctx[CpuRegister.Rdi], typeId);
        if (state is not null)
        {
            lock (state.Gate)
                result = state.Fields.ContainsKey(fieldId);
        }

        ctx[CpuRegister.Rax] = result ? 1UL : 0UL;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int Unset(CpuContext ctx, int typeId, int fieldId)
    {
        var state = TryGetState(ctx, ctx[CpuRegister.Rdi], typeId);
        if (state is not null)
        {
            lock (state.Gate)
                _ = state.Fields.Remove(fieldId);
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    // V45_EXPORT_BEGIN nid=9qGjeGStPzE
    [SysAbiExport(
        Nid = "9qGjeGStPzE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V132RequestPlayerSessionMemberPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0001(CpuContext ctx) => Destruct(ctx, 1);
    // V45_EXPORT_END nid=9qGjeGStPzE

    // V45_EXPORT_BEGIN nid=u2xZSvGh2-w
    [SysAbiExport(
        Nid = "u2xZSvGh2-w",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V132RequestPlayerSessionMemberPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0002(CpuContext ctx) => Destruct(ctx, 1);
    // V45_EXPORT_END nid=u2xZSvGh2-w

    // V45_EXPORT_BEGIN nid=daL8oRzMAx4
    [SysAbiExport(
        Nid = "daL8oRzMAx4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V126RequestPlayerSessionPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0003(CpuContext ctx) => Construct(ctx, 3);
    // V45_EXPORT_END nid=daL8oRzMAx4

    // V45_EXPORT_BEGIN nid=zCxANLkDXiY
    [SysAbiExport(
        Nid = "zCxANLkDXiY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V126RequestPlayerSessionPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0004(CpuContext ctx) => Construct(ctx, 3);
    // V45_EXPORT_END nid=zCxANLkDXiY

    // V45_EXPORT_BEGIN nid=EZER6Jtj0TM
    [SysAbiExport(
        Nid = "EZER6Jtj0TM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V126RequestPlayerSessionPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0005(CpuContext ctx) => Destruct(ctx, 3);
    // V45_EXPORT_END nid=EZER6Jtj0TM

    // V45_EXPORT_BEGIN nid=ewJgJea-W5Y
    [SysAbiExport(
        Nid = "ewJgJea-W5Y",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V126RequestPlayerSessionPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0006(CpuContext ctx) => Destruct(ctx, 3);
    // V45_EXPORT_END nid=ewJgJea-W5Y

    // V45_EXPORT_BEGIN nid=0ZbEAPArvRQ
    [SysAbiExport(
        Nid = "0ZbEAPArvRQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129RequestPlayerSessionSpectatorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0007(CpuContext ctx) => Construct(ctx, 5);
    // V45_EXPORT_END nid=0ZbEAPArvRQ

    // V45_EXPORT_BEGIN nid=FaBfkB9CzjI
    [SysAbiExport(
        Nid = "FaBfkB9CzjI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129RequestPlayerSessionSpectatorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0008(CpuContext ctx) => Construct(ctx, 5);
    // V45_EXPORT_END nid=FaBfkB9CzjI

    // V45_EXPORT_BEGIN nid=NCJjnW5g59Q
    [SysAbiExport(
        Nid = "NCJjnW5g59Q",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129RequestPlayerSessionSpectatorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0009(CpuContext ctx) => Destruct(ctx, 5);
    // V45_EXPORT_END nid=NCJjnW5g59Q

    // V45_EXPORT_BEGIN nid=wyXkR6TfWWQ
    [SysAbiExport(
        Nid = "wyXkR6TfWWQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129RequestPlayerSessionSpectatorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0010(CpuContext ctx) => Destruct(ctx, 5);
    // V45_EXPORT_END nid=wyXkR6TfWWQ

    // V45_EXPORT_BEGIN nid=9OoGDca4WW8
    [SysAbiExport(
        Nid = "9OoGDca4WW8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponseGameSessionMemberPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0011(CpuContext ctx) => Construct(ctx, 7);
    // V45_EXPORT_END nid=9OoGDca4WW8

    // V45_EXPORT_BEGIN nid=YUH2FjHcYto
    [SysAbiExport(
        Nid = "YUH2FjHcYto",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponseGameSessionMemberPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0012(CpuContext ctx) => Construct(ctx, 7);
    // V45_EXPORT_END nid=YUH2FjHcYto

    // V45_EXPORT_BEGIN nid=HiOrhyJTPEA
    [SysAbiExport(
        Nid = "HiOrhyJTPEA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponseGameSessionMemberPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0013(CpuContext ctx) => Destruct(ctx, 7);
    // V45_EXPORT_END nid=HiOrhyJTPEA

    // V45_EXPORT_BEGIN nid=TA5PTLnmxas
    [SysAbiExport(
        Nid = "TA5PTLnmxas",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponseGameSessionMemberPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0014(CpuContext ctx) => Destruct(ctx, 7);
    // V45_EXPORT_END nid=TA5PTLnmxas

    // V45_EXPORT_BEGIN nid=Oq0rbMLDllI
    [SysAbiExport(
        Nid = "Oq0rbMLDllI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V125ResponseGameSessionPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0015(CpuContext ctx) => Construct(ctx, 9);
    // V45_EXPORT_END nid=Oq0rbMLDllI

    // V45_EXPORT_BEGIN nid=m5sY-h3Z6sM
    [SysAbiExport(
        Nid = "m5sY-h3Z6sM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V125ResponseGameSessionPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0016(CpuContext ctx) => Construct(ctx, 9);
    // V45_EXPORT_END nid=m5sY-h3Z6sM

    // V45_EXPORT_BEGIN nid=JP9y7f7e7QQ
    [SysAbiExport(
        Nid = "JP9y7f7e7QQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V125ResponseGameSessionPlayer12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0017(CpuContext ctx) => GetValue(ctx, 9, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=JP9y7f7e7QQ

    // V45_EXPORT_BEGIN nid=bhWps1nBqiI
    [SysAbiExport(
        Nid = "bhWps1nBqiI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V125ResponseGameSessionPlayer12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0018(CpuContext ctx) => SetValue(ctx, 9, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=bhWps1nBqiI

    // V45_EXPORT_BEGIN nid=BkROgbo51Jw
    [SysAbiExport(
        Nid = "BkROgbo51Jw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V125ResponseGameSessionPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0019(CpuContext ctx) => Destruct(ctx, 9);
    // V45_EXPORT_END nid=BkROgbo51Jw

    // V45_EXPORT_BEGIN nid=JMKl4AB0qAY
    [SysAbiExport(
        Nid = "JMKl4AB0qAY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V125ResponseGameSessionPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0020(CpuContext ctx) => Destruct(ctx, 9);
    // V45_EXPORT_END nid=JMKl4AB0qAY

    // V45_EXPORT_BEGIN nid=8IbgLa95tAQ
    [SysAbiExport(
        Nid = "8IbgLa95tAQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128ResponseGameSessionSpectatorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0021(CpuContext ctx) => Construct(ctx, 11);
    // V45_EXPORT_END nid=8IbgLa95tAQ

    // V45_EXPORT_BEGIN nid=iG1+PK-uwdc
    [SysAbiExport(
        Nid = "iG1+PK-uwdc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128ResponseGameSessionSpectatorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0022(CpuContext ctx) => Construct(ctx, 11);
    // V45_EXPORT_END nid=iG1+PK-uwdc

    // V45_EXPORT_BEGIN nid=wzlainWo3eE
    [SysAbiExport(
        Nid = "wzlainWo3eE",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V128ResponseGameSessionSpectator12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0023(CpuContext ctx) => GetValue(ctx, 11, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=wzlainWo3eE

    // V45_EXPORT_BEGIN nid=gkbNmZpMD6s
    [SysAbiExport(
        Nid = "gkbNmZpMD6s",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128ResponseGameSessionSpectator12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0024(CpuContext ctx) => SetValue(ctx, 11, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=gkbNmZpMD6s

    // V45_EXPORT_BEGIN nid=-XG9UVGafZI
    [SysAbiExport(
        Nid = "-XG9UVGafZI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128ResponseGameSessionSpectatorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0025(CpuContext ctx) => Destruct(ctx, 11);
    // V45_EXPORT_END nid=-XG9UVGafZI

    // V45_EXPORT_BEGIN nid=Dt8AiEKkdL8
    [SysAbiExport(
        Nid = "Dt8AiEKkdL8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128ResponseGameSessionSpectatorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0026(CpuContext ctx) => Destruct(ctx, 11);
    // V45_EXPORT_END nid=Dt8AiEKkdL8

    // V45_EXPORT_BEGIN nid=Kt3N561dED8
    [SysAbiExport(
        Nid = "Kt3N561dED8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponsePlayerSessionInvitationC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0027(CpuContext ctx) => Construct(ctx, 13);
    // V45_EXPORT_END nid=Kt3N561dED8

    // V45_EXPORT_BEGIN nid=NSvsKSChyfk
    [SysAbiExport(
        Nid = "NSvsKSChyfk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponsePlayerSessionInvitationC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0028(CpuContext ctx) => Construct(ctx, 13);
    // V45_EXPORT_END nid=NSvsKSChyfk

    // V45_EXPORT_BEGIN nid=1vyq1zTl2kk
    [SysAbiExport(
        Nid = "1vyq1zTl2kk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponsePlayerSessionInvitationD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0029(CpuContext ctx) => Destruct(ctx, 13);
    // V45_EXPORT_END nid=1vyq1zTl2kk

    // V45_EXPORT_BEGIN nid=XQP7zQTiRgY
    [SysAbiExport(
        Nid = "XQP7zQTiRgY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V131ResponsePlayerSessionInvitationD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0030(CpuContext ctx) => Destruct(ctx, 13);
    // V45_EXPORT_END nid=XQP7zQTiRgY

    // V45_EXPORT_BEGIN nid=hYoWA8zezio
    [SysAbiExport(
        Nid = "hYoWA8zezio",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionMemberPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0031(CpuContext ctx) => Construct(ctx, 15);
    // V45_EXPORT_END nid=hYoWA8zezio

    // V45_EXPORT_BEGIN nid=uyBpPXo46xA
    [SysAbiExport(
        Nid = "uyBpPXo46xA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionMemberPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0032(CpuContext ctx) => Construct(ctx, 15);
    // V45_EXPORT_END nid=uyBpPXo46xA

    // V45_EXPORT_BEGIN nid=XatOH5GIHrk
    [SysAbiExport(
        Nid = "XatOH5GIHrk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionMemberPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0033(CpuContext ctx) => Destruct(ctx, 15);
    // V45_EXPORT_END nid=XatOH5GIHrk

    // V45_EXPORT_BEGIN nid=kevYNs9JoGk
    [SysAbiExport(
        Nid = "kevYNs9JoGk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionMemberPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0034(CpuContext ctx) => Destruct(ctx, 15);
    // V45_EXPORT_END nid=kevYNs9JoGk

    // V45_EXPORT_BEGIN nid=I6m4QBwYRXk
    [SysAbiExport(
        Nid = "I6m4QBwYRXk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionNonPsnPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0035(CpuContext ctx) => Construct(ctx, 17);
    // V45_EXPORT_END nid=I6m4QBwYRXk

    // V45_EXPORT_BEGIN nid=sZWxrmyqycs
    [SysAbiExport(
        Nid = "sZWxrmyqycs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionNonPsnPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0036(CpuContext ctx) => Construct(ctx, 17);
    // V45_EXPORT_END nid=sZWxrmyqycs

    // V45_EXPORT_BEGIN nid=FP1JAPcVjW0
    [SysAbiExport(
        Nid = "FP1JAPcVjW0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionNonPsnPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0037(CpuContext ctx) => Destruct(ctx, 17);
    // V45_EXPORT_END nid=FP1JAPcVjW0

    // V45_EXPORT_BEGIN nid=k2R8ICGeWjo
    [SysAbiExport(
        Nid = "k2R8ICGeWjo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V133ResponsePlayerSessionNonPsnPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0038(CpuContext ctx) => Destruct(ctx, 17);
    // V45_EXPORT_END nid=k2R8ICGeWjo

    // V45_EXPORT_BEGIN nid=CgZF8fvxU18
    [SysAbiExport(
        Nid = "CgZF8fvxU18",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127ResponsePlayerSessionPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0039(CpuContext ctx) => Construct(ctx, 19);
    // V45_EXPORT_END nid=CgZF8fvxU18

    // V45_EXPORT_BEGIN nid=FbqyBrWWUdI
    [SysAbiExport(
        Nid = "FbqyBrWWUdI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127ResponsePlayerSessionPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0040(CpuContext ctx) => Construct(ctx, 19);
    // V45_EXPORT_END nid=FbqyBrWWUdI

    // V45_EXPORT_BEGIN nid=zYTCgEvUBxU
    [SysAbiExport(
        Nid = "zYTCgEvUBxU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V127ResponsePlayerSessionPlayer12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0041(CpuContext ctx) => GetValue(ctx, 19, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=zYTCgEvUBxU

    // V45_EXPORT_BEGIN nid=76MpsmFlKQM
    [SysAbiExport(
        Nid = "76MpsmFlKQM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127ResponsePlayerSessionPlayer12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0042(CpuContext ctx) => SetValue(ctx, 19, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=76MpsmFlKQM

    // V45_EXPORT_BEGIN nid=TSL6wfivFms
    [SysAbiExport(
        Nid = "TSL6wfivFms",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127ResponsePlayerSessionPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0043(CpuContext ctx) => Destruct(ctx, 19);
    // V45_EXPORT_END nid=TSL6wfivFms

    // V45_EXPORT_BEGIN nid=wX3Ia8aX7Os
    [SysAbiExport(
        Nid = "wX3Ia8aX7Os",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127ResponsePlayerSessionPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0044(CpuContext ctx) => Destruct(ctx, 19);
    // V45_EXPORT_END nid=wX3Ia8aX7Os

    // V45_EXPORT_BEGIN nid=erwgspl4qRY
    [SysAbiExport(
        Nid = "erwgspl4qRY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V130ResponsePlayerSessionSpectatorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0045(CpuContext ctx) => Construct(ctx, 21);
    // V45_EXPORT_END nid=erwgspl4qRY

    // V45_EXPORT_BEGIN nid=ohX3f5V37FA
    [SysAbiExport(
        Nid = "ohX3f5V37FA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V130ResponsePlayerSessionSpectatorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0046(CpuContext ctx) => Construct(ctx, 21);
    // V45_EXPORT_END nid=ohX3f5V37FA

    // V45_EXPORT_BEGIN nid=F3Eg4srFrVw
    [SysAbiExport(
        Nid = "F3Eg4srFrVw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V130ResponsePlayerSessionSpectator12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0047(CpuContext ctx) => GetValue(ctx, 21, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=F3Eg4srFrVw

    // V45_EXPORT_BEGIN nid=BQ350P8PSlY
    [SysAbiExport(
        Nid = "BQ350P8PSlY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V130ResponsePlayerSessionSpectator12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0048(CpuContext ctx) => SetValue(ctx, 21, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=BQ350P8PSlY

    // V45_EXPORT_BEGIN nid=YZc2eqvJi5w
    [SysAbiExport(
        Nid = "YZc2eqvJi5w",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V130ResponsePlayerSessionSpectatorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0049(CpuContext ctx) => Destruct(ctx, 21);
    // V45_EXPORT_END nid=YZc2eqvJi5w

    // V45_EXPORT_BEGIN nid=cRN88TB6Gi8
    [SysAbiExport(
        Nid = "cRN88TB6Gi8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V130ResponsePlayerSessionSpectatorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0050(CpuContext ctx) => Destruct(ctx, 21);
    // V45_EXPORT_END nid=cRN88TB6Gi8

    // V45_EXPORT_BEGIN nid=IaxgG9UumKo
    [SysAbiExport(
        Nid = "IaxgG9UumKo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributesC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0051(CpuContext ctx) => Construct(ctx, 23);
    // V45_EXPORT_END nid=IaxgG9UumKo

    // V45_EXPORT_BEGIN nid=xbma7s2JMEk
    [SysAbiExport(
        Nid = "xbma7s2JMEk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributesC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0052(CpuContext ctx) => Construct(ctx, 23);
    // V45_EXPORT_END nid=xbma7s2JMEk

    // V45_EXPORT_BEGIN nid=3Zhv4HG-fN0
    [SysAbiExport(
        Nid = "3Zhv4HG-fN0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes14boolean10IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0053(CpuContext ctx) => IsSet(ctx, 23, 1);
    // V45_EXPORT_END nid=3Zhv4HG-fN0

    // V45_EXPORT_BEGIN nid=AVK5pOlvnc4
    [SysAbiExport(
        Nid = "AVK5pOlvnc4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean1IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0054(CpuContext ctx) => IsSet(ctx, 23, 2);
    // V45_EXPORT_END nid=AVK5pOlvnc4

    // V45_EXPORT_BEGIN nid=xkIWP8hwCtA
    [SysAbiExport(
        Nid = "xkIWP8hwCtA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean2IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0055(CpuContext ctx) => IsSet(ctx, 23, 3);
    // V45_EXPORT_END nid=xkIWP8hwCtA

    // V45_EXPORT_BEGIN nid=9lT7kN9Rnag
    [SysAbiExport(
        Nid = "9lT7kN9Rnag",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean3IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0056(CpuContext ctx) => IsSet(ctx, 23, 4);
    // V45_EXPORT_END nid=9lT7kN9Rnag

    // V45_EXPORT_BEGIN nid=EEQUMMIXylA
    [SysAbiExport(
        Nid = "EEQUMMIXylA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean4IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0057(CpuContext ctx) => IsSet(ctx, 23, 5);
    // V45_EXPORT_END nid=EEQUMMIXylA

    // V45_EXPORT_BEGIN nid=EwkmP0c0c2Q
    [SysAbiExport(
        Nid = "EwkmP0c0c2Q",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean5IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0058(CpuContext ctx) => IsSet(ctx, 23, 6);
    // V45_EXPORT_END nid=EwkmP0c0c2Q

    // V45_EXPORT_BEGIN nid=B-aDhqkzvT0
    [SysAbiExport(
        Nid = "B-aDhqkzvT0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean6IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0059(CpuContext ctx) => IsSet(ctx, 23, 7);
    // V45_EXPORT_END nid=B-aDhqkzvT0

    // V45_EXPORT_BEGIN nid=ZtiV7HeGp7M
    [SysAbiExport(
        Nid = "ZtiV7HeGp7M",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean7IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0060(CpuContext ctx) => IsSet(ctx, 23, 8);
    // V45_EXPORT_END nid=ZtiV7HeGp7M

    // V45_EXPORT_BEGIN nid=E7wqN7zhn6Y
    [SysAbiExport(
        Nid = "E7wqN7zhn6Y",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean8IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0061(CpuContext ctx) => IsSet(ctx, 23, 9);
    // V45_EXPORT_END nid=E7wqN7zhn6Y

    // V45_EXPORT_BEGIN nid=5yFprAQdMY4
    [SysAbiExport(
        Nid = "5yFprAQdMY4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13boolean9IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0062(CpuContext ctx) => IsSet(ctx, 23, 10);
    // V45_EXPORT_END nid=5yFprAQdMY4

    // V45_EXPORT_BEGIN nid=RdYwz1mA4vw
    [SysAbiExport(
        Nid = "RdYwz1mA4vw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0063(CpuContext ctx) => GetValue(ctx, 23, 2, ReturnKind.Bool);
    // V45_EXPORT_END nid=RdYwz1mA4vw

    // V45_EXPORT_BEGIN nid=3bDK4xmV5Kg
    [SysAbiExport(
        Nid = "3bDK4xmV5Kg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes12getBoolean10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0064(CpuContext ctx) => GetValue(ctx, 23, 1, ReturnKind.Bool);
    // V45_EXPORT_END nid=3bDK4xmV5Kg

    // V45_EXPORT_BEGIN nid=NoFT7fKF+5Y
    [SysAbiExport(
        Nid = "NoFT7fKF+5Y",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0065(CpuContext ctx) => GetValue(ctx, 23, 3, ReturnKind.Bool);
    // V45_EXPORT_END nid=NoFT7fKF+5Y

    // V45_EXPORT_BEGIN nid=VJnNFXSl2m0
    [SysAbiExport(
        Nid = "VJnNFXSl2m0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0066(CpuContext ctx) => GetValue(ctx, 23, 4, ReturnKind.Bool);
    // V45_EXPORT_END nid=VJnNFXSl2m0

    // V45_EXPORT_BEGIN nid=Twb4U0IdSHQ
    [SysAbiExport(
        Nid = "Twb4U0IdSHQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0067(CpuContext ctx) => GetValue(ctx, 23, 5, ReturnKind.Bool);
    // V45_EXPORT_END nid=Twb4U0IdSHQ

    // V45_EXPORT_BEGIN nid=KkdnVtWcogE
    [SysAbiExport(
        Nid = "KkdnVtWcogE",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0068(CpuContext ctx) => GetValue(ctx, 23, 6, ReturnKind.Bool);
    // V45_EXPORT_END nid=KkdnVtWcogE

    // V45_EXPORT_BEGIN nid=mMSkjbh+0VI
    [SysAbiExport(
        Nid = "mMSkjbh+0VI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0069(CpuContext ctx) => GetValue(ctx, 23, 7, ReturnKind.Bool);
    // V45_EXPORT_END nid=mMSkjbh+0VI

    // V45_EXPORT_BEGIN nid=48Bh7rcKtuY
    [SysAbiExport(
        Nid = "48Bh7rcKtuY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0070(CpuContext ctx) => GetValue(ctx, 23, 8, ReturnKind.Bool);
    // V45_EXPORT_END nid=48Bh7rcKtuY

    // V45_EXPORT_BEGIN nid=X04i3BhDv0I
    [SysAbiExport(
        Nid = "X04i3BhDv0I",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0071(CpuContext ctx) => GetValue(ctx, 23, 9, ReturnKind.Bool);
    // V45_EXPORT_END nid=X04i3BhDv0I

    // V45_EXPORT_BEGIN nid=EVGGV4de5iI
    [SysAbiExport(
        Nid = "EVGGV4de5iI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getBoolean9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0072(CpuContext ctx) => GetValue(ctx, 23, 10, ReturnKind.Bool);
    // V45_EXPORT_END nid=EVGGV4de5iI

    // V45_EXPORT_BEGIN nid=u-nocHxdjDs
    [SysAbiExport(
        Nid = "u-nocHxdjDs",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0073(CpuContext ctx) => GetValue(ctx, 23, 11, ReturnKind.U32);
    // V45_EXPORT_END nid=u-nocHxdjDs

    // V45_EXPORT_BEGIN nid=YJ+0cvknYu8
    [SysAbiExport(
        Nid = "YJ+0cvknYu8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes12getInteger10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0074(CpuContext ctx) => GetValue(ctx, 23, 12, ReturnKind.U32);
    // V45_EXPORT_END nid=YJ+0cvknYu8

    // V45_EXPORT_BEGIN nid=ryT1ZUGBCxI
    [SysAbiExport(
        Nid = "ryT1ZUGBCxI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0075(CpuContext ctx) => GetValue(ctx, 23, 13, ReturnKind.U32);
    // V45_EXPORT_END nid=ryT1ZUGBCxI

    // V45_EXPORT_BEGIN nid=L6fM17UnJ+A
    [SysAbiExport(
        Nid = "L6fM17UnJ+A",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0076(CpuContext ctx) => GetValue(ctx, 23, 14, ReturnKind.U32);
    // V45_EXPORT_END nid=L6fM17UnJ+A

    // V45_EXPORT_BEGIN nid=1tt8FddamlM
    [SysAbiExport(
        Nid = "1tt8FddamlM",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0077(CpuContext ctx) => GetValue(ctx, 23, 15, ReturnKind.U32);
    // V45_EXPORT_END nid=1tt8FddamlM

    // V45_EXPORT_BEGIN nid=0cPDxR6zOIY
    [SysAbiExport(
        Nid = "0cPDxR6zOIY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0078(CpuContext ctx) => GetValue(ctx, 23, 16, ReturnKind.U32);
    // V45_EXPORT_END nid=0cPDxR6zOIY

    // V45_EXPORT_BEGIN nid=IvZztwZzfyA
    [SysAbiExport(
        Nid = "IvZztwZzfyA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0079(CpuContext ctx) => GetValue(ctx, 23, 17, ReturnKind.U32);
    // V45_EXPORT_END nid=IvZztwZzfyA

    // V45_EXPORT_BEGIN nid=28VJv5mU8Mo
    [SysAbiExport(
        Nid = "28VJv5mU8Mo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0080(CpuContext ctx) => GetValue(ctx, 23, 18, ReturnKind.U32);
    // V45_EXPORT_END nid=28VJv5mU8Mo

    // V45_EXPORT_BEGIN nid=JaWrrHX7nfc
    [SysAbiExport(
        Nid = "JaWrrHX7nfc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0081(CpuContext ctx) => GetValue(ctx, 23, 19, ReturnKind.U32);
    // V45_EXPORT_END nid=JaWrrHX7nfc

    // V45_EXPORT_BEGIN nid=7BF+8K88NEY
    [SysAbiExport(
        Nid = "7BF+8K88NEY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11getInteger9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0082(CpuContext ctx) => GetValue(ctx, 23, 20, ReturnKind.U32);
    // V45_EXPORT_END nid=7BF+8K88NEY

    // V45_EXPORT_BEGIN nid=CYW71WY3WUU
    [SysAbiExport(
        Nid = "CYW71WY3WUU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes14integer10IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0083(CpuContext ctx) => IsSet(ctx, 23, 12);
    // V45_EXPORT_END nid=CYW71WY3WUU

    // V45_EXPORT_BEGIN nid=cvb59D5nkvk
    [SysAbiExport(
        Nid = "cvb59D5nkvk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer1IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0084(CpuContext ctx) => IsSet(ctx, 23, 11);
    // V45_EXPORT_END nid=cvb59D5nkvk

    // V45_EXPORT_BEGIN nid=3nXw7b+YjRU
    [SysAbiExport(
        Nid = "3nXw7b+YjRU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer2IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0085(CpuContext ctx) => IsSet(ctx, 23, 13);
    // V45_EXPORT_END nid=3nXw7b+YjRU

    // V45_EXPORT_BEGIN nid=hrevq-dtNW0
    [SysAbiExport(
        Nid = "hrevq-dtNW0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer3IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0086(CpuContext ctx) => IsSet(ctx, 23, 14);
    // V45_EXPORT_END nid=hrevq-dtNW0

    // V45_EXPORT_BEGIN nid=dL7wkqcugzw
    [SysAbiExport(
        Nid = "dL7wkqcugzw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer4IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0087(CpuContext ctx) => IsSet(ctx, 23, 15);
    // V45_EXPORT_END nid=dL7wkqcugzw

    // V45_EXPORT_BEGIN nid=ib13dX0Y3q8
    [SysAbiExport(
        Nid = "ib13dX0Y3q8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer5IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0088(CpuContext ctx) => IsSet(ctx, 23, 16);
    // V45_EXPORT_END nid=ib13dX0Y3q8

    // V45_EXPORT_BEGIN nid=J17Ht24BhJA
    [SysAbiExport(
        Nid = "J17Ht24BhJA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer6IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0089(CpuContext ctx) => IsSet(ctx, 23, 17);
    // V45_EXPORT_END nid=J17Ht24BhJA

    // V45_EXPORT_BEGIN nid=MXNqbivQZxY
    [SysAbiExport(
        Nid = "MXNqbivQZxY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer7IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0090(CpuContext ctx) => IsSet(ctx, 23, 18);
    // V45_EXPORT_END nid=MXNqbivQZxY

    // V45_EXPORT_BEGIN nid=+rDYDewIzM8
    [SysAbiExport(
        Nid = "+rDYDewIzM8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer8IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0091(CpuContext ctx) => IsSet(ctx, 23, 19);
    // V45_EXPORT_END nid=+rDYDewIzM8

    // V45_EXPORT_BEGIN nid=SdsTCHDTzyA
    [SysAbiExport(
        Nid = "SdsTCHDTzyA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13integer9IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0092(CpuContext ctx) => IsSet(ctx, 23, 20);
    // V45_EXPORT_END nid=SdsTCHDTzyA

    // V45_EXPORT_BEGIN nid=faa9PrpwmYU
    [SysAbiExport(
        Nid = "faa9PrpwmYU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean1ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0093(CpuContext ctx) => SetValue(ctx, 23, 2, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=faa9PrpwmYU

    // V45_EXPORT_BEGIN nid=RniTdMj3K24
    [SysAbiExport(
        Nid = "RniTdMj3K24",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes12setBoolean10ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0094(CpuContext ctx) => SetValue(ctx, 23, 1, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=RniTdMj3K24

    // V45_EXPORT_BEGIN nid=m0cZWkr9kQQ
    [SysAbiExport(
        Nid = "m0cZWkr9kQQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean2ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0095(CpuContext ctx) => SetValue(ctx, 23, 3, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=m0cZWkr9kQQ

    // V45_EXPORT_BEGIN nid=GdlvBtLAHXQ
    [SysAbiExport(
        Nid = "GdlvBtLAHXQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean3ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0096(CpuContext ctx) => SetValue(ctx, 23, 4, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=GdlvBtLAHXQ

    // V45_EXPORT_BEGIN nid=0hA35iD1YM8
    [SysAbiExport(
        Nid = "0hA35iD1YM8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean4ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0097(CpuContext ctx) => SetValue(ctx, 23, 5, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=0hA35iD1YM8

    // V45_EXPORT_BEGIN nid=ExluI5X0llk
    [SysAbiExport(
        Nid = "ExluI5X0llk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean5ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0098(CpuContext ctx) => SetValue(ctx, 23, 6, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=ExluI5X0llk

    // V45_EXPORT_BEGIN nid=9bJDrk2KoMg
    [SysAbiExport(
        Nid = "9bJDrk2KoMg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean6ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0099(CpuContext ctx) => SetValue(ctx, 23, 7, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=9bJDrk2KoMg

    // V45_EXPORT_BEGIN nid=HKHJsLAyXKA
    [SysAbiExport(
        Nid = "HKHJsLAyXKA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean7ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0100(CpuContext ctx) => SetValue(ctx, 23, 8, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=HKHJsLAyXKA

    // V45_EXPORT_BEGIN nid=1w4KTY1y7RU
    [SysAbiExport(
        Nid = "1w4KTY1y7RU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean8ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0101(CpuContext ctx) => SetValue(ctx, 23, 9, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=1w4KTY1y7RU

    // V45_EXPORT_BEGIN nid=Exk+A7qWe-o
    [SysAbiExport(
        Nid = "Exk+A7qWe-o",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setBoolean9ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0102(CpuContext ctx) => SetValue(ctx, 23, 10, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=Exk+A7qWe-o

    // V45_EXPORT_BEGIN nid=0XcSBCn-4So
    [SysAbiExport(
        Nid = "0XcSBCn-4So",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger1ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0103(CpuContext ctx) => SetValue(ctx, 23, 11, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=0XcSBCn-4So

    // V45_EXPORT_BEGIN nid=7rnbZv4SZGI
    [SysAbiExport(
        Nid = "7rnbZv4SZGI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes12setInteger10ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0104(CpuContext ctx) => SetValue(ctx, 23, 12, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=7rnbZv4SZGI

    // V45_EXPORT_BEGIN nid=tvYQoCdopVg
    [SysAbiExport(
        Nid = "tvYQoCdopVg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger2ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0105(CpuContext ctx) => SetValue(ctx, 23, 13, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=tvYQoCdopVg

    // V45_EXPORT_BEGIN nid=PMPlHieEI3A
    [SysAbiExport(
        Nid = "PMPlHieEI3A",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger3ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0106(CpuContext ctx) => SetValue(ctx, 23, 14, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=PMPlHieEI3A

    // V45_EXPORT_BEGIN nid=XgGAt7u+y3I
    [SysAbiExport(
        Nid = "XgGAt7u+y3I",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger4ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0107(CpuContext ctx) => SetValue(ctx, 23, 15, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=XgGAt7u+y3I

    // V45_EXPORT_BEGIN nid=AVNvDtVEYxA
    [SysAbiExport(
        Nid = "AVNvDtVEYxA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger5ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0108(CpuContext ctx) => SetValue(ctx, 23, 16, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=AVNvDtVEYxA

    // V45_EXPORT_BEGIN nid=BF6zFAeRAYA
    [SysAbiExport(
        Nid = "BF6zFAeRAYA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger6ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0109(CpuContext ctx) => SetValue(ctx, 23, 17, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=BF6zFAeRAYA

    // V45_EXPORT_BEGIN nid=o0G0ttErXCI
    [SysAbiExport(
        Nid = "o0G0ttErXCI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger7ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0110(CpuContext ctx) => SetValue(ctx, 23, 18, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=o0G0ttErXCI

    // V45_EXPORT_BEGIN nid=L5U9nprsR-Q
    [SysAbiExport(
        Nid = "L5U9nprsR-Q",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger8ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0111(CpuContext ctx) => SetValue(ctx, 23, 19, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=L5U9nprsR-Q

    // V45_EXPORT_BEGIN nid=Wwon-hr4q14
    [SysAbiExport(
        Nid = "Wwon-hr4q14",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes11setInteger9ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0112(CpuContext ctx) => SetValue(ctx, 23, 20, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=Wwon-hr4q14

    // V45_EXPORT_BEGIN nid=5kKmf95aeiM
    [SysAbiExport(
        Nid = "5kKmf95aeiM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0113(CpuContext ctx) => Unset(ctx, 23, 2);
    // V45_EXPORT_END nid=5kKmf95aeiM

    // V45_EXPORT_BEGIN nid=auXbCImj7Qg
    [SysAbiExport(
        Nid = "auXbCImj7Qg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes14unsetBoolean10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0114(CpuContext ctx) => Unset(ctx, 23, 1);
    // V45_EXPORT_END nid=auXbCImj7Qg

    // V45_EXPORT_BEGIN nid=NS6vfc8F5qM
    [SysAbiExport(
        Nid = "NS6vfc8F5qM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0115(CpuContext ctx) => Unset(ctx, 23, 3);
    // V45_EXPORT_END nid=NS6vfc8F5qM

    // V45_EXPORT_BEGIN nid=KBqnq2n2d5U
    [SysAbiExport(
        Nid = "KBqnq2n2d5U",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0116(CpuContext ctx) => Unset(ctx, 23, 4);
    // V45_EXPORT_END nid=KBqnq2n2d5U

    // V45_EXPORT_BEGIN nid=8pSeFangUAU
    [SysAbiExport(
        Nid = "8pSeFangUAU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0117(CpuContext ctx) => Unset(ctx, 23, 5);
    // V45_EXPORT_END nid=8pSeFangUAU

    // V45_EXPORT_BEGIN nid=XQMhx9+Xc1M
    [SysAbiExport(
        Nid = "XQMhx9+Xc1M",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0118(CpuContext ctx) => Unset(ctx, 23, 6);
    // V45_EXPORT_END nid=XQMhx9+Xc1M

    // V45_EXPORT_BEGIN nid=Dtwj0uYHras
    [SysAbiExport(
        Nid = "Dtwj0uYHras",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0119(CpuContext ctx) => Unset(ctx, 23, 7);
    // V45_EXPORT_END nid=Dtwj0uYHras

    // V45_EXPORT_BEGIN nid=qUyJrh2QnEI
    [SysAbiExport(
        Nid = "qUyJrh2QnEI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0120(CpuContext ctx) => Unset(ctx, 23, 8);
    // V45_EXPORT_END nid=qUyJrh2QnEI

    // V45_EXPORT_BEGIN nid=H8mJyVVAiOA
    [SysAbiExport(
        Nid = "H8mJyVVAiOA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0121(CpuContext ctx) => Unset(ctx, 23, 9);
    // V45_EXPORT_END nid=H8mJyVVAiOA

    // V45_EXPORT_BEGIN nid=jYzYJ61Srik
    [SysAbiExport(
        Nid = "jYzYJ61Srik",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetBoolean9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0122(CpuContext ctx) => Unset(ctx, 23, 10);
    // V45_EXPORT_END nid=jYzYJ61Srik

    // V45_EXPORT_BEGIN nid=5I0KrtwvlSw
    [SysAbiExport(
        Nid = "5I0KrtwvlSw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0123(CpuContext ctx) => Unset(ctx, 23, 11);
    // V45_EXPORT_END nid=5I0KrtwvlSw

    // V45_EXPORT_BEGIN nid=wKvnAYtcaPs
    [SysAbiExport(
        Nid = "wKvnAYtcaPs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes14unsetInteger10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0124(CpuContext ctx) => Unset(ctx, 23, 12);
    // V45_EXPORT_END nid=wKvnAYtcaPs

    // V45_EXPORT_BEGIN nid=BKdEIHS1zbQ
    [SysAbiExport(
        Nid = "BKdEIHS1zbQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0125(CpuContext ctx) => Unset(ctx, 23, 13);
    // V45_EXPORT_END nid=BKdEIHS1zbQ

    // V45_EXPORT_BEGIN nid=A1HoXBZt3nQ
    [SysAbiExport(
        Nid = "A1HoXBZt3nQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0126(CpuContext ctx) => Unset(ctx, 23, 14);
    // V45_EXPORT_END nid=A1HoXBZt3nQ

    // V45_EXPORT_BEGIN nid=ruvLq5s4ZzU
    [SysAbiExport(
        Nid = "ruvLq5s4ZzU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0127(CpuContext ctx) => Unset(ctx, 23, 15);
    // V45_EXPORT_END nid=ruvLq5s4ZzU

    // V45_EXPORT_BEGIN nid=q+8lk-9sRWU
    [SysAbiExport(
        Nid = "q+8lk-9sRWU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0128(CpuContext ctx) => Unset(ctx, 23, 16);
    // V45_EXPORT_END nid=q+8lk-9sRWU

    // V45_EXPORT_BEGIN nid=9aNFpPJWKls
    [SysAbiExport(
        Nid = "9aNFpPJWKls",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0129(CpuContext ctx) => Unset(ctx, 23, 17);
    // V45_EXPORT_END nid=9aNFpPJWKls

    // V45_EXPORT_BEGIN nid=Q0kH-Vmn50Y
    [SysAbiExport(
        Nid = "Q0kH-Vmn50Y",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0130(CpuContext ctx) => Unset(ctx, 23, 18);
    // V45_EXPORT_END nid=Q0kH-Vmn50Y

    // V45_EXPORT_BEGIN nid=Qq52iAV5GtU
    [SysAbiExport(
        Nid = "Qq52iAV5GtU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0131(CpuContext ctx) => Unset(ctx, 23, 19);
    // V45_EXPORT_END nid=Qq52iAV5GtU

    // V45_EXPORT_BEGIN nid=07-D+uOdr4U
    [SysAbiExport(
        Nid = "07-D+uOdr4U",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributes13unsetInteger9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0132(CpuContext ctx) => Unset(ctx, 23, 20);
    // V45_EXPORT_END nid=07-D+uOdr4U

    // V45_EXPORT_BEGIN nid=kE-pP+SNCrU
    [SysAbiExport(
        Nid = "kE-pP+SNCrU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributesD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0133(CpuContext ctx) => Destruct(ctx, 23);
    // V45_EXPORT_END nid=kE-pP+SNCrU

    // V45_EXPORT_BEGIN nid=o-GBjVbCTjM
    [SysAbiExport(
        Nid = "o-GBjVbCTjM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V116SearchAttributesD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0134(CpuContext ctx) => Destruct(ctx, 23);
    // V45_EXPORT_END nid=o-GBjVbCTjM

    // V45_EXPORT_BEGIN nid=4ZXj4yVA40U
    [SysAbiExport(
        Nid = "4ZXj4yVA40U",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115SearchConditionC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0135(CpuContext ctx) => Construct(ctx, 25);
    // V45_EXPORT_END nid=4ZXj4yVA40U

    // V45_EXPORT_BEGIN nid=LcWsOD7iZTw
    [SysAbiExport(
        Nid = "LcWsOD7iZTw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115SearchConditionC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0136(CpuContext ctx) => Construct(ctx, 25);
    // V45_EXPORT_END nid=LcWsOD7iZTw

    // V45_EXPORT_BEGIN nid=IcPfdX-tqP8
    [SysAbiExport(
        Nid = "IcPfdX-tqP8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115SearchConditionD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0137(CpuContext ctx) => Destruct(ctx, 25);
    // V45_EXPORT_END nid=IcPfdX-tqP8

    // V45_EXPORT_BEGIN nid=nTrpPLSPKw0
    [SysAbiExport(
        Nid = "nTrpPLSPKw0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115SearchConditionD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0138(CpuContext ctx) => Destruct(ctx, 25);
    // V45_EXPORT_END nid=nTrpPLSPKw0

    // V45_EXPORT_BEGIN nid=-VQ44oZKoSg
    [SysAbiExport(
        Nid = "-VQ44oZKoSg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117SearchGameSessionC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0139(CpuContext ctx) => Construct(ctx, 27);
    // V45_EXPORT_END nid=-VQ44oZKoSg

    // V45_EXPORT_BEGIN nid=wR0f0av3W9I
    [SysAbiExport(
        Nid = "wR0f0av3W9I",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117SearchGameSessionC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0140(CpuContext ctx) => Construct(ctx, 27);
    // V45_EXPORT_END nid=wR0f0av3W9I

    // V45_EXPORT_BEGIN nid=IgjnabrP4Sg
    [SysAbiExport(
        Nid = "IgjnabrP4Sg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117SearchGameSessionD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0141(CpuContext ctx) => Destruct(ctx, 27);
    // V45_EXPORT_END nid=IgjnabrP4Sg

    // V45_EXPORT_BEGIN nid=S3ggPj1HPVw
    [SysAbiExport(
        Nid = "S3ggPj1HPVw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117SearchGameSessionD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0142(CpuContext ctx) => Destruct(ctx, 27);
    // V45_EXPORT_END nid=S3ggPj1HPVw

    // V45_EXPORT_BEGIN nid=Ayyzf0loiqk
    [SysAbiExport(
        Nid = "Ayyzf0loiqk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V12ToC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0143(CpuContext ctx) => Construct(ctx, 29);
    // V45_EXPORT_END nid=Ayyzf0loiqk

    // V45_EXPORT_BEGIN nid=sDEcg2NhaQ4
    [SysAbiExport(
        Nid = "sDEcg2NhaQ4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V12ToC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0144(CpuContext ctx) => Construct(ctx, 29);
    // V45_EXPORT_END nid=sDEcg2NhaQ4

    // V45_EXPORT_BEGIN nid=Q8Zqv9vJYjA
    [SysAbiExport(
        Nid = "Q8Zqv9vJYjA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V12To12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0145(CpuContext ctx) => GetValue(ctx, 29, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=Q8Zqv9vJYjA

    // V45_EXPORT_BEGIN nid=-Qq59KDuvLw
    [SysAbiExport(
        Nid = "-Qq59KDuvLw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V12To12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0146(CpuContext ctx) => SetValue(ctx, 29, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=-Qq59KDuvLw

    // V45_EXPORT_BEGIN nid=O6yZtj-d5tI
    [SysAbiExport(
        Nid = "O6yZtj-d5tI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V12ToD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0147(CpuContext ctx) => Destruct(ctx, 29);
    // V45_EXPORT_END nid=O6yZtj-d5tI

    // V45_EXPORT_BEGIN nid=yBlLjtA44w8
    [SysAbiExport(
        Nid = "yBlLjtA44w8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V12ToD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0148(CpuContext ctx) => Destruct(ctx, 29);
    // V45_EXPORT_END nid=yBlLjtA44w8

    // V45_EXPORT_BEGIN nid=s5el2evQ0cM
    [SysAbiExport(
        Nid = "s5el2evQ0cM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForReadC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0149(CpuContext ctx) => Construct(ctx, 31);
    // V45_EXPORT_END nid=s5el2evQ0cM

    // V45_EXPORT_BEGIN nid=yZA4dYfnPvo
    [SysAbiExport(
        Nid = "yZA4dYfnPvo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForReadC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0150(CpuContext ctx) => Construct(ctx, 31);
    // V45_EXPORT_END nid=yZA4dYfnPvo

    // V45_EXPORT_BEGIN nid=ch-tDZCG1+k
    [SysAbiExport(
        Nid = "ch-tDZCG1+k",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForRead20getInvitationInvalidEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0151(CpuContext ctx) => GetValue(ctx, 31, 1, ReturnKind.Bool);
    // V45_EXPORT_END nid=ch-tDZCG1+k

    // V45_EXPORT_BEGIN nid=vdk6rLp8ivc
    [SysAbiExport(
        Nid = "vdk6rLp8ivc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForRead22invitationInvalidIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0152(CpuContext ctx) => IsSet(ctx, 31, 1);
    // V45_EXPORT_END nid=vdk6rLp8ivc

    // V45_EXPORT_BEGIN nid=RMtQC0TMcIo
    [SysAbiExport(
        Nid = "RMtQC0TMcIo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForRead20setInvitationInvalidERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0153(CpuContext ctx) => SetValue(ctx, 31, 1, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=RMtQC0TMcIo

    // V45_EXPORT_BEGIN nid=GNSJkp2i+2s
    [SysAbiExport(
        Nid = "GNSJkp2i+2s",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForRead22unsetInvitationInvalidEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0154(CpuContext ctx) => Unset(ctx, 31, 1);
    // V45_EXPORT_END nid=GNSJkp2i+2s

    // V45_EXPORT_BEGIN nid=DtUG7-AGqcI
    [SysAbiExport(
        Nid = "DtUG7-AGqcI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForReadD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0155(CpuContext ctx) => Destruct(ctx, 31);
    // V45_EXPORT_END nid=DtUG7-AGqcI

    // V45_EXPORT_BEGIN nid=Q71VA70Qzk4
    [SysAbiExport(
        Nid = "Q71VA70Qzk4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V136UsersPlayerSessionsInvitationForReadD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0156(CpuContext ctx) => Destruct(ctx, 31);
    // V45_EXPORT_END nid=Q71VA70Qzk4

    // V45_EXPORT_BEGIN nid=NXeaI-+8AdA
    [SysAbiExport(
        Nid = "NXeaI-+8AdA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0157(CpuContext ctx) => Construct(ctx, 33);
    // V45_EXPORT_END nid=NXeaI-+8AdA

    // V45_EXPORT_BEGIN nid=VzZIOWx4fRY
    [SysAbiExport(
        Nid = "VzZIOWx4fRY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0158(CpuContext ctx) => Construct(ctx, 33);
    // V45_EXPORT_END nid=VzZIOWx4fRY

    // V45_EXPORT_BEGIN nid=g6oPi2XqTnQ
    [SysAbiExport(
        Nid = "g6oPi2XqTnQ",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBody17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0159(CpuContext ctx) => GetValue(ctx, 33, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=g6oPi2XqTnQ

    // V45_EXPORT_BEGIN nid=i4nmZrhI6tY
    [SysAbiExport(
        Nid = "i4nmZrhI6tY",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBody8getValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0160(CpuContext ctx) => GetValue(ctx, 33, 2, ReturnKind.U64);
    // V45_EXPORT_END nid=i4nmZrhI6tY

    // V45_EXPORT_BEGIN nid=WbIr4Spv0wA
    [SysAbiExport(
        Nid = "WbIr4Spv0wA",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBody19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0161(CpuContext ctx) => IsSet(ctx, 33, 1);
    // V45_EXPORT_END nid=WbIr4Spv0wA

    // V45_EXPORT_BEGIN nid=ovJChufCjXc
    [SysAbiExport(
        Nid = "ovJChufCjXc",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBody17setNpServiceLabelERKj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0162(CpuContext ctx) => SetValue(ctx, 33, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=ovJChufCjXc

    // V45_EXPORT_BEGIN nid=GcBBIozjw1g
    [SysAbiExport(
        Nid = "GcBBIozjw1g",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBody8setValueERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0163(CpuContext ctx) => SetValue(ctx, 33, 2, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=GcBBIozjw1g

    // V45_EXPORT_BEGIN nid=WywAFglkLug
    [SysAbiExport(
        Nid = "WywAFglkLug",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBody19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0164(CpuContext ctx) => Unset(ctx, 33, 1);
    // V45_EXPORT_END nid=WywAFglkLug

    // V45_EXPORT_BEGIN nid=1wy8bq-Us9M
    [SysAbiExport(
        Nid = "1wy8bq-Us9M",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0165(CpuContext ctx) => Destruct(ctx, 33);
    // V45_EXPORT_END nid=1wy8bq-Us9M

    // V45_EXPORT_BEGIN nid=9msLSBEGafY
    [SysAbiExport(
        Nid = "9msLSBEGafY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128AddAndGetVariableRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0166(CpuContext ctx) => Destruct(ctx, 33);
    // V45_EXPORT_END nid=9msLSBEGafY

    // V45_EXPORT_BEGIN nid=T10xlsNDjFU
    [SysAbiExport(
        Nid = "T10xlsNDjFU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi27DownloadDataResponseHeadersD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0167(CpuContext ctx) => Destruct(ctx, 35);
    // V45_EXPORT_END nid=T10xlsNDjFU

    // V45_EXPORT_BEGIN nid=cJOvwTknjnE
    [SysAbiExport(
        Nid = "cJOvwTknjnE",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi27DownloadDataResponseHeadersD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0168(CpuContext ctx) => Destruct(ctx, 35);
    // V45_EXPORT_END nid=cJOvwTknjnE

    // V45_EXPORT_BEGIN nid=ESP+o70WUcU
    [SysAbiExport(
        Nid = "ESP+o70WUcU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataBySlot17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0169(CpuContext ctx) => GetValue(ctx, 36, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=ESP+o70WUcU

    // V45_EXPORT_BEGIN nid=N9jV0y31xMg
    [SysAbiExport(
        Nid = "N9jV0y31xMg",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataBySlot9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0170(CpuContext ctx) => GetValue(ctx, 36, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=N9jV0y31xMg

    // V45_EXPORT_BEGIN nid=BCATnoGUjrs
    [SysAbiExport(
        Nid = "BCATnoGUjrs",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataBySlot17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0171(CpuContext ctx) => SetValue(ctx, 36, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=BCATnoGUjrs

    // V45_EXPORT_BEGIN nid=pbODKYfA7pk
    [SysAbiExport(
        Nid = "pbODKYfA7pk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataBySlot9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0172(CpuContext ctx) => SetValue(ctx, 36, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=pbODKYfA7pk

    // V45_EXPORT_BEGIN nid=5MbNiacAJAk
    [SysAbiExport(
        Nid = "5MbNiacAJAk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataBySlot19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0173(CpuContext ctx) => Unset(ctx, 36, 1);
    // V45_EXPORT_END nid=5MbNiacAJAk

    // V45_EXPORT_BEGIN nid=1YEU5F0Bm98
    [SysAbiExport(
        Nid = "1YEU5F0Bm98",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataBySlotD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0174(CpuContext ctx) => Destruct(ctx, 36);
    // V45_EXPORT_END nid=1YEU5F0Bm98

    // V45_EXPORT_BEGIN nid=6MdlRs2aIlM
    [SysAbiExport(
        Nid = "6MdlRs2aIlM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataBySlotD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0175(CpuContext ctx) => Destruct(ctx, 36);
    // V45_EXPORT_END nid=6MdlRs2aIlM

    // V45_EXPORT_BEGIN nid=uITsIlaiYBc
    [SysAbiExport(
        Nid = "uITsIlaiYBc",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataByUser17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0176(CpuContext ctx) => GetValue(ctx, 37, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=uITsIlaiYBc

    // V45_EXPORT_BEGIN nid=Uy+spyud5AY
    [SysAbiExport(
        Nid = "Uy+spyud5AY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataByUser17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0177(CpuContext ctx) => SetValue(ctx, 37, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=Uy+spyud5AY

    // V45_EXPORT_BEGIN nid=ppaQfUmmLyw
    [SysAbiExport(
        Nid = "ppaQfUmmLyw",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataByUser19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0178(CpuContext ctx) => Unset(ctx, 37, 1);
    // V45_EXPORT_END nid=ppaQfUmmLyw

    // V45_EXPORT_BEGIN nid=PyAkLlm5O98
    [SysAbiExport(
        Nid = "PyAkLlm5O98",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataByUserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0179(CpuContext ctx) => Destruct(ctx, 37);
    // V45_EXPORT_END nid=PyAkLlm5O98

    // V45_EXPORT_BEGIN nid=jisqpUJlaPA
    [SysAbiExport(
        Nid = "jisqpUJlaPA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi32ParameterToDeleteMultiDataByUserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0180(CpuContext ctx) => Destruct(ctx, 37);
    // V45_EXPORT_END nid=jisqpUJlaPA

    // V45_EXPORT_BEGIN nid=mMyvDodUdvI
    [SysAbiExport(
        Nid = "mMyvDodUdvI",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi23ParameterToDownloadData17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0181(CpuContext ctx) => GetValue(ctx, 38, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=mMyvDodUdvI

    // V45_EXPORT_BEGIN nid=jcBgznNmWQU
    [SysAbiExport(
        Nid = "jcBgznNmWQU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi23ParameterToDownloadData9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0182(CpuContext ctx) => GetValue(ctx, 38, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=jcBgznNmWQU

    // V45_EXPORT_BEGIN nid=9KX8MktrvHA
    [SysAbiExport(
        Nid = "9KX8MktrvHA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi23ParameterToDownloadData17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0183(CpuContext ctx) => SetValue(ctx, 38, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=9KX8MktrvHA

    // V45_EXPORT_BEGIN nid=KN3KH+ZEPzM
    [SysAbiExport(
        Nid = "KN3KH+ZEPzM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi23ParameterToDownloadData9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0184(CpuContext ctx) => SetValue(ctx, 38, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=KN3KH+ZEPzM

    // V45_EXPORT_BEGIN nid=1MkSo--2MNI
    [SysAbiExport(
        Nid = "1MkSo--2MNI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi23ParameterToDownloadData19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0185(CpuContext ctx) => Unset(ctx, 38, 1);
    // V45_EXPORT_END nid=1MkSo--2MNI

    // V45_EXPORT_BEGIN nid=0UNp2Ey5bw4
    [SysAbiExport(
        Nid = "0UNp2Ey5bw4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi23ParameterToDownloadDataD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0186(CpuContext ctx) => Destruct(ctx, 38);
    // V45_EXPORT_END nid=0UNp2Ey5bw4

    // V45_EXPORT_BEGIN nid=HbfdxoUWpyI
    [SysAbiExport(
        Nid = "HbfdxoUWpyI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi23ParameterToDownloadDataD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0187(CpuContext ctx) => Destruct(ctx, 38);
    // V45_EXPORT_END nid=HbfdxoUWpyI

    // V45_EXPORT_BEGIN nid=H-YRL0+Nin4
    [SysAbiExport(
        Nid = "H-YRL0+Nin4",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot8getlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0188(CpuContext ctx) => GetValue(ctx, 39, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=H-YRL0+Nin4

    // V45_EXPORT_BEGIN nid=xK6UXGpTPtU
    [SysAbiExport(
        Nid = "xK6UXGpTPtU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0189(CpuContext ctx) => GetValue(ctx, 39, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=xK6UXGpTPtU

    // V45_EXPORT_BEGIN nid=pKI0Za-Ggf0
    [SysAbiExport(
        Nid = "pKI0Za-Ggf0",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot9getoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0190(CpuContext ctx) => GetValue(ctx, 39, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=pKI0Za-Ggf0

    // V45_EXPORT_BEGIN nid=N8KbL-Cm1oU
    [SysAbiExport(
        Nid = "N8KbL-Cm1oU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0191(CpuContext ctx) => GetValue(ctx, 39, 4, ReturnKind.U32);
    // V45_EXPORT_END nid=N8KbL-Cm1oU

    // V45_EXPORT_BEGIN nid=60PxGiP12yY
    [SysAbiExport(
        Nid = "60PxGiP12yY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot8setlimitEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0192(CpuContext ctx) => SetValue(ctx, 39, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=60PxGiP12yY

    // V45_EXPORT_BEGIN nid=GVEbyNroOEI
    [SysAbiExport(
        Nid = "GVEbyNroOEI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0193(CpuContext ctx) => SetValue(ctx, 39, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=GVEbyNroOEI

    // V45_EXPORT_BEGIN nid=ZYpuc8benBo
    [SysAbiExport(
        Nid = "ZYpuc8benBo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot9setoffsetEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0194(CpuContext ctx) => SetValue(ctx, 39, 3, ValueSource.Register, false);
    // V45_EXPORT_END nid=ZYpuc8benBo

    // V45_EXPORT_BEGIN nid=foRxDkhZxEQ
    [SysAbiExport(
        Nid = "foRxDkhZxEQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0195(CpuContext ctx) => SetValue(ctx, 39, 4, ValueSource.Register, false);
    // V45_EXPORT_END nid=foRxDkhZxEQ

    // V45_EXPORT_BEGIN nid=nSp+IAqg3JU
    [SysAbiExport(
        Nid = "nSp+IAqg3JU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot10unsetlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0196(CpuContext ctx) => Unset(ctx, 39, 1);
    // V45_EXPORT_END nid=nSp+IAqg3JU

    // V45_EXPORT_BEGIN nid=pjtBReGInLo
    [SysAbiExport(
        Nid = "pjtBReGInLo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0197(CpuContext ctx) => Unset(ctx, 39, 2);
    // V45_EXPORT_END nid=pjtBReGInLo

    // V45_EXPORT_BEGIN nid=IKehnzGx75M
    [SysAbiExport(
        Nid = "IKehnzGx75M",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlot11unsetoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0198(CpuContext ctx) => Unset(ctx, 39, 3);
    // V45_EXPORT_END nid=IKehnzGx75M

    // V45_EXPORT_BEGIN nid=+vQWu4q6j9Y
    [SysAbiExport(
        Nid = "+vQWu4q6j9Y",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlotD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0199(CpuContext ctx) => Destruct(ctx, 39);
    // V45_EXPORT_END nid=+vQWu4q6j9Y

    // V45_EXPORT_BEGIN nid=nIWt+5qjWmo
    [SysAbiExport(
        Nid = "nIWt+5qjWmo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesBySlotD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0200(CpuContext ctx) => Destruct(ctx, 39);
    // V45_EXPORT_END nid=nIWt+5qjWmo

    // V45_EXPORT_BEGIN nid=-7A9qfZj08o
    [SysAbiExport(
        Nid = "-7A9qfZj08o",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser8getlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0201(CpuContext ctx) => GetValue(ctx, 40, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=-7A9qfZj08o

    // V45_EXPORT_BEGIN nid=1SFyRaQDT3M
    [SysAbiExport(
        Nid = "1SFyRaQDT3M",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0202(CpuContext ctx) => GetValue(ctx, 40, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=1SFyRaQDT3M

    // V45_EXPORT_BEGIN nid=yAkEH7s6xNs
    [SysAbiExport(
        Nid = "yAkEH7s6xNs",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser9getoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0203(CpuContext ctx) => GetValue(ctx, 40, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=yAkEH7s6xNs

    // V45_EXPORT_BEGIN nid=HIkwgAuwsAo
    [SysAbiExport(
        Nid = "HIkwgAuwsAo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser8setlimitEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0204(CpuContext ctx) => SetValue(ctx, 40, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=HIkwgAuwsAo

    // V45_EXPORT_BEGIN nid=yU4-BCjWhHo
    [SysAbiExport(
        Nid = "yU4-BCjWhHo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0205(CpuContext ctx) => SetValue(ctx, 40, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=yU4-BCjWhHo

    // V45_EXPORT_BEGIN nid=B2omeKs6CsM
    [SysAbiExport(
        Nid = "B2omeKs6CsM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser9setoffsetEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0206(CpuContext ctx) => SetValue(ctx, 40, 3, ValueSource.Register, false);
    // V45_EXPORT_END nid=B2omeKs6CsM

    // V45_EXPORT_BEGIN nid=xJPWSymYFhs
    [SysAbiExport(
        Nid = "xJPWSymYFhs",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser10unsetlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0207(CpuContext ctx) => Unset(ctx, 40, 1);
    // V45_EXPORT_END nid=xJPWSymYFhs

    // V45_EXPORT_BEGIN nid=3avu10wAzl4
    [SysAbiExport(
        Nid = "3avu10wAzl4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0208(CpuContext ctx) => Unset(ctx, 40, 2);
    // V45_EXPORT_END nid=3avu10wAzl4

    // V45_EXPORT_BEGIN nid=NNbViWnK7Ss
    [SysAbiExport(
        Nid = "NNbViWnK7Ss",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUser11unsetoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0209(CpuContext ctx) => Unset(ctx, 40, 3);
    // V45_EXPORT_END nid=NNbViWnK7Ss

    // V45_EXPORT_BEGIN nid=a4q15LI1a4E
    [SysAbiExport(
        Nid = "a4q15LI1a4E",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0210(CpuContext ctx) => Destruct(ctx, 40);
    // V45_EXPORT_END nid=a4q15LI1a4E

    // V45_EXPORT_BEGIN nid=e-S6iuDl2xk
    [SysAbiExport(
        Nid = "e-S6iuDl2xk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi37ParameterToGetMultiDataStatusesByUserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0211(CpuContext ctx) => Destruct(ctx, 40);
    // V45_EXPORT_END nid=e-S6iuDl2xk

    // V45_EXPORT_BEGIN nid=Ow5mMPNmDGI
    [SysAbiExport(
        Nid = "Ow5mMPNmDGI",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi22ParameterToSetDataInfo9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0212(CpuContext ctx) => GetValue(ctx, 41, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=Ow5mMPNmDGI

    // V45_EXPORT_BEGIN nid=nUp6I7HlQNM
    [SysAbiExport(
        Nid = "nUp6I7HlQNM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi22ParameterToSetDataInfo9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0213(CpuContext ctx) => SetValue(ctx, 41, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=nUp6I7HlQNM

    // V45_EXPORT_BEGIN nid=R6ZajxSYd8E
    [SysAbiExport(
        Nid = "R6ZajxSYd8E",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi22ParameterToSetDataInfoD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0214(CpuContext ctx) => Destruct(ctx, 41);
    // V45_EXPORT_END nid=R6ZajxSYd8E

    // V45_EXPORT_BEGIN nid=saK0rH25IW4
    [SysAbiExport(
        Nid = "saK0rH25IW4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi22ParameterToSetDataInfoD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0215(CpuContext ctx) => Destruct(ctx, 41);
    // V45_EXPORT_END nid=saK0rH25IW4

    // V45_EXPORT_BEGIN nid=pAUHU0koAWs
    [SysAbiExport(
        Nid = "pAUHU0koAWs",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0216(CpuContext ctx) => GetValue(ctx, 42, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=pAUHU0koAWs

    // V45_EXPORT_BEGIN nid=vCn-9B2GUQc
    [SysAbiExport(
        Nid = "vCn-9B2GUQc",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData21getxPsnNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0217(CpuContext ctx) => GetValue(ctx, 42, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=vCn-9B2GUQc

    // V45_EXPORT_BEGIN nid=W1zF0Tniuw0
    [SysAbiExport(
        Nid = "W1zF0Tniuw0",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData42getxPsnTcsComparedLastUpdatedUserAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0218(CpuContext ctx) => GetValue(ctx, 42, 3, ReturnKind.U64);
    // V45_EXPORT_END nid=W1zF0Tniuw0

    // V45_EXPORT_BEGIN nid=naOwex5mTn4
    [SysAbiExport(
        Nid = "naOwex5mTn4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0219(CpuContext ctx) => SetValue(ctx, 42, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=naOwex5mTn4

    // V45_EXPORT_BEGIN nid=AqY6riP-PjM
    [SysAbiExport(
        Nid = "AqY6riP-PjM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData21setxPsnNpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0220(CpuContext ctx) => SetValue(ctx, 42, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=AqY6riP-PjM

    // V45_EXPORT_BEGIN nid=2Ch5cl2wXgQ
    [SysAbiExport(
        Nid = "2Ch5cl2wXgQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData42setxPsnTcsComparedLastUpdatedUserAccountIdEm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0221(CpuContext ctx) => SetValue(ctx, 42, 3, ValueSource.Register, false);
    // V45_EXPORT_END nid=2Ch5cl2wXgQ

    // V45_EXPORT_BEGIN nid=qh3HbUTyK78
    [SysAbiExport(
        Nid = "qh3HbUTyK78",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData23unsetxPsnNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0222(CpuContext ctx) => Unset(ctx, 42, 2);
    // V45_EXPORT_END nid=qh3HbUTyK78

    // V45_EXPORT_BEGIN nid=02rTCbd1Gsc
    [SysAbiExport(
        Nid = "02rTCbd1Gsc",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadData44unsetxPsnTcsComparedLastUpdatedUserAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0223(CpuContext ctx) => Unset(ctx, 42, 3);
    // V45_EXPORT_END nid=02rTCbd1Gsc

    // V45_EXPORT_BEGIN nid=GQLXi2KQaXk
    [SysAbiExport(
        Nid = "GQLXi2KQaXk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadDataD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0224(CpuContext ctx) => Destruct(ctx, 42);
    // V45_EXPORT_END nid=GQLXi2KQaXk

    // V45_EXPORT_BEGIN nid=IYdmFM04Qhg
    [SysAbiExport(
        Nid = "IYdmFM04Qhg",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi21ParameterToUploadDataD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0225(CpuContext ctx) => Destruct(ctx, 42);
    // V45_EXPORT_END nid=IYdmFM04Qhg

    // V45_EXPORT_BEGIN nid=OxeNeflLGhc
    [SysAbiExport(
        Nid = "OxeNeflLGhc",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi42ParameterWithBinaryRequestBodyToUploadDataD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0226(CpuContext ctx) => Destruct(ctx, 43);
    // V45_EXPORT_END nid=OxeNeflLGhc

    // V45_EXPORT_BEGIN nid=x3G5RSdGS+A
    [SysAbiExport(
        Nid = "x3G5RSdGS+A",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi42ParameterWithBinaryRequestBodyToUploadDataD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0227(CpuContext ctx) => Destruct(ctx, 43);
    // V45_EXPORT_END nid=x3G5RSdGS+A

    // V45_EXPORT_BEGIN nid=31vzT36+cXM
    [SysAbiExport(
        Nid = "31vzT36+cXM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi26SetDataInfoResponseHeadersD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0228(CpuContext ctx) => Destruct(ctx, 44);
    // V45_EXPORT_END nid=31vzT36+cXM

    // V45_EXPORT_BEGIN nid=9ibZzkBkQyY
    [SysAbiExport(
        Nid = "9ibZzkBkQyY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi26SetDataInfoResponseHeadersD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0229(CpuContext ctx) => Destruct(ctx, 44);
    // V45_EXPORT_END nid=9ibZzkBkQyY

    // V45_EXPORT_BEGIN nid=8NvMTqWOwo4
    [SysAbiExport(
        Nid = "8NvMTqWOwo4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi25UploadDataResponseHeadersD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0230(CpuContext ctx) => Destruct(ctx, 45);
    // V45_EXPORT_END nid=8NvMTqWOwo4

    // V45_EXPORT_BEGIN nid=jUxkuMrcdNA
    [SysAbiExport(
        Nid = "jUxkuMrcdNA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V17DataApi25UploadDataResponseHeadersD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0231(CpuContext ctx) => Destruct(ctx, 45);
    // V45_EXPORT_END nid=jUxkuMrcdNA

    // V45_EXPORT_BEGIN nid=-R0AqmVskaQ
    [SysAbiExport(
        Nid = "-R0AqmVskaQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatusC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0232(CpuContext ctx) => Construct(ctx, 47);
    // V45_EXPORT_END nid=-R0AqmVskaQ

    // V45_EXPORT_BEGIN nid=Kk4QlGJ+xZs
    [SysAbiExport(
        Nid = "Kk4QlGJ+xZs",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatusC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0233(CpuContext ctx) => Construct(ctx, 47);
    // V45_EXPORT_END nid=Kk4QlGJ+xZs

    // V45_EXPORT_BEGIN nid=8MZi4-tr47E
    [SysAbiExport(
        Nid = "8MZi4-tr47E",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus13dataSizeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0234(CpuContext ctx) => IsSet(ctx, 47, 1);
    // V45_EXPORT_END nid=8MZi4-tr47E

    // V45_EXPORT_BEGIN nid=PsX657reZeo
    [SysAbiExport(
        Nid = "PsX657reZeo",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus11getDataSizeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0235(CpuContext ctx) => GetValue(ctx, 47, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=PsX657reZeo

    // V45_EXPORT_BEGIN nid=XCtf+23QT0k
    [SysAbiExport(
        Nid = "XCtf+23QT0k",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus9getSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0236(CpuContext ctx) => GetValue(ctx, 47, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=XCtf+23QT0k

    // V45_EXPORT_BEGIN nid=M+clD3pQf5E
    [SysAbiExport(
        Nid = "M+clD3pQf5E",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus11setDataSizeERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0237(CpuContext ctx) => SetValue(ctx, 47, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=M+clD3pQf5E

    // V45_EXPORT_BEGIN nid=CMwT-KpOFYk
    [SysAbiExport(
        Nid = "CMwT-KpOFYk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus9setSlotIdERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0238(CpuContext ctx) => SetValue(ctx, 47, 2, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=CMwT-KpOFYk

    // V45_EXPORT_BEGIN nid=PR8r-TCBz0U
    [SysAbiExport(
        Nid = "PR8r-TCBz0U",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus11slotIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0239(CpuContext ctx) => IsSet(ctx, 47, 2);
    // V45_EXPORT_END nid=PR8r-TCBz0U

    // V45_EXPORT_BEGIN nid=GGqI60EEL-w
    [SysAbiExport(
        Nid = "GGqI60EEL-w",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus13unsetDataSizeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0240(CpuContext ctx) => Unset(ctx, 47, 1);
    // V45_EXPORT_END nid=GGqI60EEL-w

    // V45_EXPORT_BEGIN nid=guaqRqZCe2g
    [SysAbiExport(
        Nid = "guaqRqZCe2g",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatus11unsetSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0241(CpuContext ctx) => Unset(ctx, 47, 2);
    // V45_EXPORT_END nid=guaqRqZCe2g

    // V45_EXPORT_BEGIN nid=+LjPW03VdFg
    [SysAbiExport(
        Nid = "+LjPW03VdFg",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatusD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0242(CpuContext ctx) => Destruct(ctx, 47);
    // V45_EXPORT_END nid=+LjPW03VdFg

    // V45_EXPORT_BEGIN nid=IyrC1lVqedo
    [SysAbiExport(
        Nid = "IyrC1lVqedo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V110DataStatusD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0243(CpuContext ctx) => Destruct(ctx, 47);
    // V45_EXPORT_END nid=IyrC1lVqedo

    // V45_EXPORT_BEGIN nid=0t5T4m4CLuA
    [SysAbiExport(
        Nid = "0t5T4m4CLuA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0244(CpuContext ctx) => Construct(ctx, 49);
    // V45_EXPORT_END nid=0t5T4m4CLuA

    // V45_EXPORT_BEGIN nid=DbUZH7fs1Pw
    [SysAbiExport(
        Nid = "DbUZH7fs1Pw",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0245(CpuContext ctx) => Construct(ctx, 49);
    // V45_EXPORT_END nid=DbUZH7fs1Pw

    // V45_EXPORT_BEGIN nid=BUmydJk3RJY
    [SysAbiExport(
        Nid = "BUmydJk3RJY",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V15Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0246(CpuContext ctx) => GetValue(ctx, 49, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=BUmydJk3RJY

    // V45_EXPORT_BEGIN nid=XIU-YfHVjk8
    [SysAbiExport(
        Nid = "XIU-YfHVjk8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15Error7setCodeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0247(CpuContext ctx) => SetValue(ctx, 49, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=XIU-YfHVjk8

    // V45_EXPORT_BEGIN nid=-uSVGcnoANY
    [SysAbiExport(
        Nid = "-uSVGcnoANY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0248(CpuContext ctx) => Destruct(ctx, 49);
    // V45_EXPORT_END nid=-uSVGcnoANY

    // V45_EXPORT_BEGIN nid=wVO9QbbpOBU
    [SysAbiExport(
        Nid = "wVO9QbbpOBU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0249(CpuContext ctx) => Destruct(ctx, 49);
    // V45_EXPORT_END nid=wVO9QbbpOBU

    // V45_EXPORT_BEGIN nid=88menXYWpBk
    [SysAbiExport(
        Nid = "88menXYWpBk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V113ErrorResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0250(CpuContext ctx) => Construct(ctx, 51);
    // V45_EXPORT_END nid=88menXYWpBk

    // V45_EXPORT_BEGIN nid=zCZqrp8OkFY
    [SysAbiExport(
        Nid = "zCZqrp8OkFY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V113ErrorResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0251(CpuContext ctx) => Construct(ctx, 51);
    // V45_EXPORT_END nid=zCZqrp8OkFY

    // V45_EXPORT_BEGIN nid=97PkESu6iVk
    [SysAbiExport(
        Nid = "97PkESu6iVk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V113ErrorResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0252(CpuContext ctx) => Destruct(ctx, 51);
    // V45_EXPORT_END nid=97PkESu6iVk

    // V45_EXPORT_BEGIN nid=UYjiUSe9wPw
    [SysAbiExport(
        Nid = "UYjiUSe9wPw",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V113ErrorResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0253(CpuContext ctx) => Destruct(ctx, 51);
    // V45_EXPORT_END nid=UYjiUSe9wPw

    // V45_EXPORT_BEGIN nid=n6mQTBd5lj4
    [SysAbiExport(
        Nid = "n6mQTBd5lj4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0254(CpuContext ctx) => Construct(ctx, 53);
    // V45_EXPORT_END nid=n6mQTBd5lj4

    // V45_EXPORT_BEGIN nid=rRt32ct3kys
    [SysAbiExport(
        Nid = "rRt32ct3kys",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0255(CpuContext ctx) => Construct(ctx, 53);
    // V45_EXPORT_END nid=rRt32ct3kys

    // V45_EXPORT_BEGIN nid=tIkZcQS39gU
    [SysAbiExport(
        Nid = "tIkZcQS39gU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody8getLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0256(CpuContext ctx) => GetValue(ctx, 53, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=tIkZcQS39gU

    // V45_EXPORT_BEGIN nid=HJFAd2piPpA
    [SysAbiExport(
        Nid = "HJFAd2piPpA",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody9getOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0257(CpuContext ctx) => GetValue(ctx, 53, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=HJFAd2piPpA

    // V45_EXPORT_BEGIN nid=Is+nI7Hq9jU
    [SysAbiExport(
        Nid = "Is+nI7Hq9jU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody23getTotalDataStatusCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0258(CpuContext ctx) => GetValue(ctx, 53, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=Is+nI7Hq9jU

    // V45_EXPORT_BEGIN nid=0Gqs466l0tQ
    [SysAbiExport(
        Nid = "0Gqs466l0tQ",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody10limitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0259(CpuContext ctx) => IsSet(ctx, 53, 1);
    // V45_EXPORT_END nid=0Gqs466l0tQ

    // V45_EXPORT_BEGIN nid=zCIiOlzrCLs
    [SysAbiExport(
        Nid = "zCIiOlzrCLs",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody11offsetIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0260(CpuContext ctx) => IsSet(ctx, 53, 2);
    // V45_EXPORT_END nid=zCIiOlzrCLs

    // V45_EXPORT_BEGIN nid=TTVT7IBxsrM
    [SysAbiExport(
        Nid = "TTVT7IBxsrM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody8setLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0261(CpuContext ctx) => SetValue(ctx, 53, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=TTVT7IBxsrM

    // V45_EXPORT_BEGIN nid=7aQeX4x1mJQ
    [SysAbiExport(
        Nid = "7aQeX4x1mJQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody9setOffsetERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0262(CpuContext ctx) => SetValue(ctx, 53, 2, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=7aQeX4x1mJQ

    // V45_EXPORT_BEGIN nid=tc1rmiwcvl0
    [SysAbiExport(
        Nid = "tc1rmiwcvl0",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody23setTotalDataStatusCountERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0263(CpuContext ctx) => SetValue(ctx, 53, 3, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=tc1rmiwcvl0

    // V45_EXPORT_BEGIN nid=rM1pB40ImUI
    [SysAbiExport(
        Nid = "rM1pB40ImUI",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody25totalDataStatusCountIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0264(CpuContext ctx) => IsSet(ctx, 53, 3);
    // V45_EXPORT_END nid=rM1pB40ImUI

    // V45_EXPORT_BEGIN nid=AZsPtFoHAZ8
    [SysAbiExport(
        Nid = "AZsPtFoHAZ8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody10unsetLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0265(CpuContext ctx) => Unset(ctx, 53, 1);
    // V45_EXPORT_END nid=AZsPtFoHAZ8

    // V45_EXPORT_BEGIN nid=l36UM64Z+i4
    [SysAbiExport(
        Nid = "l36UM64Z+i4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody11unsetOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0266(CpuContext ctx) => Unset(ctx, 53, 2);
    // V45_EXPORT_END nid=l36UM64Z+i4

    // V45_EXPORT_BEGIN nid=+jqwsobz5uo
    [SysAbiExport(
        Nid = "+jqwsobz5uo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBody25unsetTotalDataStatusCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0267(CpuContext ctx) => Unset(ctx, 53, 3);
    // V45_EXPORT_END nid=+jqwsobz5uo

    // V45_EXPORT_BEGIN nid=MZZ0g9Y7pBc
    [SysAbiExport(
        Nid = "MZZ0g9Y7pBc",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0268(CpuContext ctx) => Destruct(ctx, 53);
    // V45_EXPORT_END nid=MZZ0g9Y7pBc

    // V45_EXPORT_BEGIN nid=i7LkLAsV0WU
    [SysAbiExport(
        Nid = "i7LkLAsV0WU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V132GetMultiDataStatusesResponseBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0269(CpuContext ctx) => Destruct(ctx, 53);
    // V45_EXPORT_END nid=i7LkLAsV0WU

    // V45_EXPORT_BEGIN nid=6LDkOHIpueE
    [SysAbiExport(
        Nid = "6LDkOHIpueE",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0270(CpuContext ctx) => Construct(ctx, 55);
    // V45_EXPORT_END nid=6LDkOHIpueE

    // V45_EXPORT_BEGIN nid=q88nARTCDrE
    [SysAbiExport(
        Nid = "q88nARTCDrE",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0271(CpuContext ctx) => Construct(ctx, 55);
    // V45_EXPORT_END nid=q88nARTCDrE

    // V45_EXPORT_BEGIN nid=QAZtKuy2wIg
    [SysAbiExport(
        Nid = "QAZtKuy2wIg",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody8getLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0272(CpuContext ctx) => GetValue(ctx, 55, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=QAZtKuy2wIg

    // V45_EXPORT_BEGIN nid=pdwofrxAnAs
    [SysAbiExport(
        Nid = "pdwofrxAnAs",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody9getOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0273(CpuContext ctx) => GetValue(ctx, 55, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=pdwofrxAnAs

    // V45_EXPORT_BEGIN nid=tQgPrFvN92g
    [SysAbiExport(
        Nid = "tQgPrFvN92g",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody21getTotalVariableCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0274(CpuContext ctx) => GetValue(ctx, 55, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=tQgPrFvN92g

    // V45_EXPORT_BEGIN nid=lifv9YgJaYc
    [SysAbiExport(
        Nid = "lifv9YgJaYc",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody10limitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0275(CpuContext ctx) => IsSet(ctx, 55, 1);
    // V45_EXPORT_END nid=lifv9YgJaYc

    // V45_EXPORT_BEGIN nid=IPkyP6ig4sc
    [SysAbiExport(
        Nid = "IPkyP6ig4sc",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody11offsetIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0276(CpuContext ctx) => IsSet(ctx, 55, 2);
    // V45_EXPORT_END nid=IPkyP6ig4sc

    // V45_EXPORT_BEGIN nid=7l2Jv4Pu9RA
    [SysAbiExport(
        Nid = "7l2Jv4Pu9RA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody8setLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0277(CpuContext ctx) => SetValue(ctx, 55, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=7l2Jv4Pu9RA

    // V45_EXPORT_BEGIN nid=sbPqKt-e0bk
    [SysAbiExport(
        Nid = "sbPqKt-e0bk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody9setOffsetERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0278(CpuContext ctx) => SetValue(ctx, 55, 2, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=sbPqKt-e0bk

    // V45_EXPORT_BEGIN nid=589Iv4F6keU
    [SysAbiExport(
        Nid = "589Iv4F6keU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody21setTotalVariableCountERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0279(CpuContext ctx) => SetValue(ctx, 55, 3, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=589Iv4F6keU

    // V45_EXPORT_BEGIN nid=WV9y653hEmc
    [SysAbiExport(
        Nid = "WV9y653hEmc",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody23totalVariableCountIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0280(CpuContext ctx) => IsSet(ctx, 55, 3);
    // V45_EXPORT_END nid=WV9y653hEmc

    // V45_EXPORT_BEGIN nid=C9YhqadaXzQ
    [SysAbiExport(
        Nid = "C9YhqadaXzQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody10unsetLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0281(CpuContext ctx) => Unset(ctx, 55, 1);
    // V45_EXPORT_END nid=C9YhqadaXzQ

    // V45_EXPORT_BEGIN nid=0rH-NteAXpo
    [SysAbiExport(
        Nid = "0rH-NteAXpo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody11unsetOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0282(CpuContext ctx) => Unset(ctx, 55, 2);
    // V45_EXPORT_END nid=0rH-NteAXpo

    // V45_EXPORT_BEGIN nid=Pn77BeNF79U
    [SysAbiExport(
        Nid = "Pn77BeNF79U",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBody23unsetTotalVariableCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0283(CpuContext ctx) => Unset(ctx, 55, 3);
    // V45_EXPORT_END nid=Pn77BeNF79U

    // V45_EXPORT_BEGIN nid=1fer52I2524
    [SysAbiExport(
        Nid = "1fer52I2524",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0284(CpuContext ctx) => Destruct(ctx, 55);
    // V45_EXPORT_END nid=1fer52I2524

    // V45_EXPORT_BEGIN nid=PoUnroC+e4c
    [SysAbiExport(
        Nid = "PoUnroC+e4c",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V129GetMultiVariablesResponseBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0285(CpuContext ctx) => Destruct(ctx, 55);
    // V45_EXPORT_END nid=PoUnroC+e4c

    // V45_EXPORT_BEGIN nid=GmKS0bnd+BI
    [SysAbiExport(
        Nid = "GmKS0bnd+BI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariableC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0286(CpuContext ctx) => Construct(ctx, 57);
    // V45_EXPORT_END nid=GmKS0bnd+BI

    // V45_EXPORT_BEGIN nid=rea47PfCUwU
    [SysAbiExport(
        Nid = "rea47PfCUwU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariableC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0287(CpuContext ctx) => Construct(ctx, 57);
    // V45_EXPORT_END nid=rea47PfCUwU

    // V45_EXPORT_BEGIN nid=OeZaNLCgxdA
    [SysAbiExport(
        Nid = "OeZaNLCgxdA",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable9getSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0288(CpuContext ctx) => GetValue(ctx, 57, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=OeZaNLCgxdA

    // V45_EXPORT_BEGIN nid=XvfHZol5M80
    [SysAbiExport(
        Nid = "XvfHZol5M80",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable8getValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0289(CpuContext ctx) => GetValue(ctx, 57, 2, ReturnKind.U64);
    // V45_EXPORT_END nid=XvfHZol5M80

    // V45_EXPORT_BEGIN nid=5xgZx3AvaBQ
    [SysAbiExport(
        Nid = "5xgZx3AvaBQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable9setSlotIdERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0290(CpuContext ctx) => SetValue(ctx, 57, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=5xgZx3AvaBQ

    // V45_EXPORT_BEGIN nid=FeRX0tbFuoA
    [SysAbiExport(
        Nid = "FeRX0tbFuoA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable8setValueERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0291(CpuContext ctx) => SetValue(ctx, 57, 2, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=FeRX0tbFuoA

    // V45_EXPORT_BEGIN nid=vy-0DOQobkU
    [SysAbiExport(
        Nid = "vy-0DOQobkU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable11slotIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0292(CpuContext ctx) => IsSet(ctx, 57, 1);
    // V45_EXPORT_END nid=vy-0DOQobkU

    // V45_EXPORT_BEGIN nid=f6Lr-fvn0Ww
    [SysAbiExport(
        Nid = "f6Lr-fvn0Ww",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable11unsetSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0293(CpuContext ctx) => Unset(ctx, 57, 1);
    // V45_EXPORT_END nid=f6Lr-fvn0Ww

    // V45_EXPORT_BEGIN nid=B19ESkRVY58
    [SysAbiExport(
        Nid = "B19ESkRVY58",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable10unsetValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0294(CpuContext ctx) => Unset(ctx, 57, 2);
    // V45_EXPORT_END nid=B19ESkRVY58

    // V45_EXPORT_BEGIN nid=ylTRxi27Neg
    [SysAbiExport(
        Nid = "ylTRxi27Neg",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariable10valueIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0295(CpuContext ctx) => IsSet(ctx, 57, 2);
    // V45_EXPORT_END nid=ylTRxi27Neg

    // V45_EXPORT_BEGIN nid=fdFUsLHjp2M
    [SysAbiExport(
        Nid = "fdFUsLHjp2M",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariableD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0296(CpuContext ctx) => Destruct(ctx, 57);
    // V45_EXPORT_END nid=fdFUsLHjp2M

    // V45_EXPORT_BEGIN nid=qyqQWtdNIPE
    [SysAbiExport(
        Nid = "qyqQWtdNIPE",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V118IdempotentVariableD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0297(CpuContext ctx) => Destruct(ctx, 57);
    // V45_EXPORT_END nid=qyqQWtdNIPE

    // V45_EXPORT_BEGIN nid=QB0CUuGxDR8
    [SysAbiExport(
        Nid = "QB0CUuGxDR8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V115LastUpdatedUserC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0298(CpuContext ctx) => Construct(ctx, 59);
    // V45_EXPORT_END nid=QB0CUuGxDR8

    // V45_EXPORT_BEGIN nid=oM1W-49YawQ
    [SysAbiExport(
        Nid = "oM1W-49YawQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V115LastUpdatedUserC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0299(CpuContext ctx) => Construct(ctx, 59);
    // V45_EXPORT_END nid=oM1W-49YawQ

    // V45_EXPORT_BEGIN nid=W0RPTmyiPXs
    [SysAbiExport(
        Nid = "W0RPTmyiPXs",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V115LastUpdatedUserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0300(CpuContext ctx) => Destruct(ctx, 59);
    // V45_EXPORT_END nid=W0RPTmyiPXs

    // V45_EXPORT_BEGIN nid=dBbFlmweYqQ
    [SysAbiExport(
        Nid = "dBbFlmweYqQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V115LastUpdatedUserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0301(CpuContext ctx) => Destruct(ctx, 59);
    // V45_EXPORT_END nid=dBbFlmweYqQ

    // V45_EXPORT_BEGIN nid=MzkrJ8VJuP4
    [SysAbiExport(
        Nid = "MzkrJ8VJuP4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15OwnerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0302(CpuContext ctx) => Construct(ctx, 61);
    // V45_EXPORT_END nid=MzkrJ8VJuP4

    // V45_EXPORT_BEGIN nid=ZL6+aTbbWQ0
    [SysAbiExport(
        Nid = "ZL6+aTbbWQ0",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15OwnerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0303(CpuContext ctx) => Construct(ctx, 61);
    // V45_EXPORT_END nid=ZL6+aTbbWQ0

    // V45_EXPORT_BEGIN nid=MqjgIzSKi+Q
    [SysAbiExport(
        Nid = "MqjgIzSKi+Q",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15OwnerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0304(CpuContext ctx) => Destruct(ctx, 61);
    // V45_EXPORT_END nid=MqjgIzSKi+Q

    // V45_EXPORT_BEGIN nid=m+xB1LOH8Ig
    [SysAbiExport(
        Nid = "m+xB1LOH8Ig",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V15OwnerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0305(CpuContext ctx) => Destruct(ctx, 61);
    // V45_EXPORT_END nid=m+xB1LOH8Ig

    // V45_EXPORT_BEGIN nid=Ofhy8Ky4rEk
    [SysAbiExport(
        Nid = "Ofhy8Ky4rEk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0306(CpuContext ctx) => Construct(ctx, 63);
    // V45_EXPORT_END nid=Ofhy8Ky4rEk

    // V45_EXPORT_BEGIN nid=P3anr7ige48
    [SysAbiExport(
        Nid = "P3anr7ige48",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0307(CpuContext ctx) => Construct(ctx, 63);
    // V45_EXPORT_END nid=P3anr7ige48

    // V45_EXPORT_BEGIN nid=ARuPIlCJ1zA
    [SysAbiExport(
        Nid = "ARuPIlCJ1zA",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBody17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0308(CpuContext ctx) => GetValue(ctx, 63, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=ARuPIlCJ1zA

    // V45_EXPORT_BEGIN nid=cGNyPw9-8h8
    [SysAbiExport(
        Nid = "cGNyPw9-8h8",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBody19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0309(CpuContext ctx) => IsSet(ctx, 63, 1);
    // V45_EXPORT_END nid=cGNyPw9-8h8

    // V45_EXPORT_BEGIN nid=MgkNIcmCFyI
    [SysAbiExport(
        Nid = "MgkNIcmCFyI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBody17setNpServiceLabelERKj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0310(CpuContext ctx) => SetValue(ctx, 63, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=MgkNIcmCFyI

    // V45_EXPORT_BEGIN nid=+IPktZAvm18
    [SysAbiExport(
        Nid = "+IPktZAvm18",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBody19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0311(CpuContext ctx) => Unset(ctx, 63, 1);
    // V45_EXPORT_END nid=+IPktZAvm18

    // V45_EXPORT_BEGIN nid=jLV2Nv3i98s
    [SysAbiExport(
        Nid = "jLV2Nv3i98s",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0312(CpuContext ctx) => Destruct(ctx, 63);
    // V45_EXPORT_END nid=jLV2Nv3i98s

    // V45_EXPORT_BEGIN nid=v7a3UnyBmN4
    [SysAbiExport(
        Nid = "v7a3UnyBmN4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122SetDataInfoRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0313(CpuContext ctx) => Destruct(ctx, 63);
    // V45_EXPORT_END nid=v7a3UnyBmN4

    // V45_EXPORT_BEGIN nid=CEDQEB+Hx2c
    [SysAbiExport(
        Nid = "CEDQEB+Hx2c",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0314(CpuContext ctx) => Construct(ctx, 65);
    // V45_EXPORT_END nid=CEDQEB+Hx2c

    // V45_EXPORT_BEGIN nid=KrdhTDT+eQ8
    [SysAbiExport(
        Nid = "KrdhTDT+eQ8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0315(CpuContext ctx) => Construct(ctx, 65);
    // V45_EXPORT_END nid=KrdhTDT+eQ8

    // V45_EXPORT_BEGIN nid=EvVXKPeuyiY
    [SysAbiExport(
        Nid = "EvVXKPeuyiY",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBody17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0316(CpuContext ctx) => GetValue(ctx, 65, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=EvVXKPeuyiY

    // V45_EXPORT_BEGIN nid=gwF55cdJDlo
    [SysAbiExport(
        Nid = "gwF55cdJDlo",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBody19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0317(CpuContext ctx) => IsSet(ctx, 65, 1);
    // V45_EXPORT_END nid=gwF55cdJDlo

    // V45_EXPORT_BEGIN nid=6WU-DPPrc2E
    [SysAbiExport(
        Nid = "6WU-DPPrc2E",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBody17setNpServiceLabelERKj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0318(CpuContext ctx) => SetValue(ctx, 65, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=6WU-DPPrc2E

    // V45_EXPORT_BEGIN nid=WD4aqU0ocLA
    [SysAbiExport(
        Nid = "WD4aqU0ocLA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBody19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0319(CpuContext ctx) => Unset(ctx, 65, 1);
    // V45_EXPORT_END nid=WD4aqU0ocLA

    // V45_EXPORT_BEGIN nid=2tocZojNaag
    [SysAbiExport(
        Nid = "2tocZojNaag",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0320(CpuContext ctx) => Destruct(ctx, 65);
    // V45_EXPORT_END nid=2tocZojNaag

    // V45_EXPORT_BEGIN nid=gXUgaT+IxrY
    [SysAbiExport(
        Nid = "gXUgaT+IxrY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V128SetMultiVariablesRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0321(CpuContext ctx) => Destruct(ctx, 65);
    // V45_EXPORT_END nid=gXUgaT+IxrY

    // V45_EXPORT_BEGIN nid=NkdF8DH6S9Y
    [SysAbiExport(
        Nid = "NkdF8DH6S9Y",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variablesC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0322(CpuContext ctx) => Construct(ctx, 67);
    // V45_EXPORT_END nid=NkdF8DH6S9Y

    // V45_EXPORT_BEGIN nid=rIgTGKsjMac
    [SysAbiExport(
        Nid = "rIgTGKsjMac",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variablesC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0323(CpuContext ctx) => Construct(ctx, 67);
    // V45_EXPORT_END nid=rIgTGKsjMac

    // V45_EXPORT_BEGIN nid=KWR1lRjS0lA
    [SysAbiExport(
        Nid = "KWR1lRjS0lA",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables9getSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0324(CpuContext ctx) => GetValue(ctx, 67, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=KWR1lRjS0lA

    // V45_EXPORT_BEGIN nid=qivys5MfyN8
    [SysAbiExport(
        Nid = "qivys5MfyN8",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables8getValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0325(CpuContext ctx) => GetValue(ctx, 67, 2, ReturnKind.U64);
    // V45_EXPORT_END nid=qivys5MfyN8

    // V45_EXPORT_BEGIN nid=iu2D0k7hojY
    [SysAbiExport(
        Nid = "iu2D0k7hojY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables9setSlotIdERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0326(CpuContext ctx) => SetValue(ctx, 67, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=iu2D0k7hojY

    // V45_EXPORT_BEGIN nid=v1SALP2Agbk
    [SysAbiExport(
        Nid = "v1SALP2Agbk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables8setValueERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0327(CpuContext ctx) => SetValue(ctx, 67, 2, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=v1SALP2Agbk

    // V45_EXPORT_BEGIN nid=RfxWyFo0HiU
    [SysAbiExport(
        Nid = "RfxWyFo0HiU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables11slotIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0328(CpuContext ctx) => IsSet(ctx, 67, 1);
    // V45_EXPORT_END nid=RfxWyFo0HiU

    // V45_EXPORT_BEGIN nid=8mYuWmK7qes
    [SysAbiExport(
        Nid = "8mYuWmK7qes",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables11unsetSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0329(CpuContext ctx) => Unset(ctx, 67, 1);
    // V45_EXPORT_END nid=8mYuWmK7qes

    // V45_EXPORT_BEGIN nid=3rHmvvhjDBs
    [SysAbiExport(
        Nid = "3rHmvvhjDBs",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables10unsetValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0330(CpuContext ctx) => Unset(ctx, 67, 2);
    // V45_EXPORT_END nid=3rHmvvhjDBs

    // V45_EXPORT_BEGIN nid=xRaguf2MZ0c
    [SysAbiExport(
        Nid = "xRaguf2MZ0c",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variables10valueIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0331(CpuContext ctx) => IsSet(ctx, 67, 2);
    // V45_EXPORT_END nid=xRaguf2MZ0c

    // V45_EXPORT_BEGIN nid=5UFz30Wboyg
    [SysAbiExport(
        Nid = "5UFz30Wboyg",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variablesD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0332(CpuContext ctx) => Destruct(ctx, 67);
    // V45_EXPORT_END nid=5UFz30Wboyg

    // V45_EXPORT_BEGIN nid=nn8b-zfOB44
    [SysAbiExport(
        Nid = "nn8b-zfOB44",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V138SetMultiVariablesRequestBody_variablesD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0333(CpuContext ctx) => Destruct(ctx, 67);
    // V45_EXPORT_END nid=nn8b-zfOB44

    // V45_EXPORT_BEGIN nid=5hbCmQT4nO4
    [SysAbiExport(
        Nid = "5hbCmQT4nO4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0334(CpuContext ctx) => Construct(ctx, 69);
    // V45_EXPORT_END nid=5hbCmQT4nO4

    // V45_EXPORT_BEGIN nid=MQjASpmw8NQ
    [SysAbiExport(
        Nid = "MQjASpmw8NQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0335(CpuContext ctx) => Construct(ctx, 69);
    // V45_EXPORT_END nid=MQjASpmw8NQ

    // V45_EXPORT_BEGIN nid=TNFvCbFICBM
    [SysAbiExport(
        Nid = "TNFvCbFICBM",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody18comparedValueIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0336(CpuContext ctx) => IsSet(ctx, 69, 1);
    // V45_EXPORT_END nid=TNFvCbFICBM

    // V45_EXPORT_BEGIN nid=nqQpr4WAfcw
    [SysAbiExport(
        Nid = "nqQpr4WAfcw",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody16getComparedValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0337(CpuContext ctx) => GetValue(ctx, 69, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=nqQpr4WAfcw

    // V45_EXPORT_BEGIN nid=2ikmh6yBG8Y
    [SysAbiExport(
        Nid = "2ikmh6yBG8Y",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0338(CpuContext ctx) => GetValue(ctx, 69, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=2ikmh6yBG8Y

    // V45_EXPORT_BEGIN nid=3cL6gACIbDI
    [SysAbiExport(
        Nid = "3cL6gACIbDI",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody8getValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0339(CpuContext ctx) => GetValue(ctx, 69, 3, ReturnKind.U64);
    // V45_EXPORT_END nid=3cL6gACIbDI

    // V45_EXPORT_BEGIN nid=qUBsmDiLFoU
    [SysAbiExport(
        Nid = "qUBsmDiLFoU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0340(CpuContext ctx) => IsSet(ctx, 69, 2);
    // V45_EXPORT_END nid=qUBsmDiLFoU

    // V45_EXPORT_BEGIN nid=QbP+Qr9wdno
    [SysAbiExport(
        Nid = "QbP+Qr9wdno",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody16setComparedValueERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0341(CpuContext ctx) => SetValue(ctx, 69, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=QbP+Qr9wdno

    // V45_EXPORT_BEGIN nid=Rk-LaLv8rzI
    [SysAbiExport(
        Nid = "Rk-LaLv8rzI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody17setNpServiceLabelERKj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0342(CpuContext ctx) => SetValue(ctx, 69, 2, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=Rk-LaLv8rzI

    // V45_EXPORT_BEGIN nid=-4yJ1w7Q9bs
    [SysAbiExport(
        Nid = "-4yJ1w7Q9bs",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody8setValueERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0343(CpuContext ctx) => SetValue(ctx, 69, 3, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=-4yJ1w7Q9bs

    // V45_EXPORT_BEGIN nid=rRy2xbCR5ag
    [SysAbiExport(
        Nid = "rRy2xbCR5ag",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody18unsetComparedValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0344(CpuContext ctx) => Unset(ctx, 69, 1);
    // V45_EXPORT_END nid=rRy2xbCR5ag

    // V45_EXPORT_BEGIN nid=NkpJ6zsg-ag
    [SysAbiExport(
        Nid = "NkpJ6zsg-ag",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBody19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0345(CpuContext ctx) => Unset(ctx, 69, 2);
    // V45_EXPORT_END nid=NkpJ6zsg-ag

    // V45_EXPORT_BEGIN nid=7mEn9EDhcn0
    [SysAbiExport(
        Nid = "7mEn9EDhcn0",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0346(CpuContext ctx) => Destruct(ctx, 69);
    // V45_EXPORT_END nid=7mEn9EDhcn0

    // V45_EXPORT_BEGIN nid=LrCdNgQvy2o
    [SysAbiExport(
        Nid = "LrCdNgQvy2o",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V136SetVariableWithConditionsRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0347(CpuContext ctx) => Destruct(ctx, 69);
    // V45_EXPORT_END nid=LrCdNgQvy2o

    // V45_EXPORT_BEGIN nid=DIvJVQ3aBR8
    [SysAbiExport(
        Nid = "DIvJVQ3aBR8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122UploadDataResponseBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0348(CpuContext ctx) => Construct(ctx, 71);
    // V45_EXPORT_END nid=DIvJVQ3aBR8

    // V45_EXPORT_BEGIN nid=g7g1+cBiEKo
    [SysAbiExport(
        Nid = "g7g1+cBiEKo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122UploadDataResponseBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0349(CpuContext ctx) => Construct(ctx, 71);
    // V45_EXPORT_END nid=g7g1+cBiEKo

    // V45_EXPORT_BEGIN nid=3nJgHQwirAU
    [SysAbiExport(
        Nid = "3nJgHQwirAU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122UploadDataResponseBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0350(CpuContext ctx) => Destruct(ctx, 71);
    // V45_EXPORT_END nid=3nJgHQwirAU

    // V45_EXPORT_BEGIN nid=51zlE5TH2-8
    [SysAbiExport(
        Nid = "51zlE5TH2-8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V122UploadDataResponseBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0351(CpuContext ctx) => Destruct(ctx, 71);
    // V45_EXPORT_END nid=51zlE5TH2-8

    // V45_EXPORT_BEGIN nid=PvXIwJfJvnU
    [SysAbiExport(
        Nid = "PvXIwJfJvnU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18VariableC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0352(CpuContext ctx) => Construct(ctx, 73);
    // V45_EXPORT_END nid=PvXIwJfJvnU

    // V45_EXPORT_BEGIN nid=ztWW11yMTzU
    [SysAbiExport(
        Nid = "ztWW11yMTzU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18VariableC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0353(CpuContext ctx) => Construct(ctx, 73);
    // V45_EXPORT_END nid=ztWW11yMTzU

    // V45_EXPORT_BEGIN nid=-cLIfSisruo
    [SysAbiExport(
        Nid = "-cLIfSisruo",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V18Variable12getPrevValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0354(CpuContext ctx) => GetValue(ctx, 73, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=-cLIfSisruo

    // V45_EXPORT_BEGIN nid=q-Ue2YZGwYU
    [SysAbiExport(
        Nid = "q-Ue2YZGwYU",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V18Variable9getSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0355(CpuContext ctx) => GetValue(ctx, 73, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=q-Ue2YZGwYU

    // V45_EXPORT_BEGIN nid=wFdynVv+1oQ
    [SysAbiExport(
        Nid = "wFdynVv+1oQ",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V18Variable8getValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0356(CpuContext ctx) => GetValue(ctx, 73, 3, ReturnKind.U64);
    // V45_EXPORT_END nid=wFdynVv+1oQ

    // V45_EXPORT_BEGIN nid=LOoCMH7rHLE
    [SysAbiExport(
        Nid = "LOoCMH7rHLE",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V18Variable14prevValueIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0357(CpuContext ctx) => IsSet(ctx, 73, 1);
    // V45_EXPORT_END nid=LOoCMH7rHLE

    // V45_EXPORT_BEGIN nid=LyLvydnxMpQ
    [SysAbiExport(
        Nid = "LyLvydnxMpQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18Variable12setPrevValueERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0358(CpuContext ctx) => SetValue(ctx, 73, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=LyLvydnxMpQ

    // V45_EXPORT_BEGIN nid=Xelhwqhd5Wo
    [SysAbiExport(
        Nid = "Xelhwqhd5Wo",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18Variable9setSlotIdERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0359(CpuContext ctx) => SetValue(ctx, 73, 2, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=Xelhwqhd5Wo

    // V45_EXPORT_BEGIN nid=+ievrHfHGsg
    [SysAbiExport(
        Nid = "+ievrHfHGsg",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18Variable8setValueERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0360(CpuContext ctx) => SetValue(ctx, 73, 3, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=+ievrHfHGsg

    // V45_EXPORT_BEGIN nid=x+e5jfR5gbc
    [SysAbiExport(
        Nid = "x+e5jfR5gbc",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V18Variable11slotIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0361(CpuContext ctx) => IsSet(ctx, 73, 2);
    // V45_EXPORT_END nid=x+e5jfR5gbc

    // V45_EXPORT_BEGIN nid=78i6RsGXf4k
    [SysAbiExport(
        Nid = "78i6RsGXf4k",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18Variable14unsetPrevValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0362(CpuContext ctx) => Unset(ctx, 73, 1);
    // V45_EXPORT_END nid=78i6RsGXf4k

    // V45_EXPORT_BEGIN nid=HFKE9Vcdt7o
    [SysAbiExport(
        Nid = "HFKE9Vcdt7o",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18Variable11unsetSlotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0363(CpuContext ctx) => Unset(ctx, 73, 2);
    // V45_EXPORT_END nid=HFKE9Vcdt7o

    // V45_EXPORT_BEGIN nid=PCgbanhN-MU
    [SysAbiExport(
        Nid = "PCgbanhN-MU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18Variable10unsetValueEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0364(CpuContext ctx) => Unset(ctx, 73, 3);
    // V45_EXPORT_END nid=PCgbanhN-MU

    // V45_EXPORT_BEGIN nid=2OwIlPSvjKw
    [SysAbiExport(
        Nid = "2OwIlPSvjKw",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V18Variable10valueIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0365(CpuContext ctx) => IsSet(ctx, 73, 3);
    // V45_EXPORT_END nid=2OwIlPSvjKw

    // V45_EXPORT_BEGIN nid=M4K8XwzqwOs
    [SysAbiExport(
        Nid = "M4K8XwzqwOs",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18VariableD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0366(CpuContext ctx) => Destruct(ctx, 73);
    // V45_EXPORT_END nid=M4K8XwzqwOs

    // V45_EXPORT_BEGIN nid=zaKEz6GvobM
    [SysAbiExport(
        Nid = "zaKEz6GvobM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V18VariableD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0367(CpuContext ctx) => Destruct(ctx, 73);
    // V45_EXPORT_END nid=zaKEz6GvobM

    // V45_EXPORT_BEGIN nid=IBdWgzE+PC4
    [SysAbiExport(
        Nid = "IBdWgzE+PC4",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi28ParameterToAddAndGetVariable9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0368(CpuContext ctx) => GetValue(ctx, 75, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=IBdWgzE+PC4

    // V45_EXPORT_BEGIN nid=dJ46OIIsuHw
    [SysAbiExport(
        Nid = "dJ46OIIsuHw",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi28ParameterToAddAndGetVariable9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0369(CpuContext ctx) => SetValue(ctx, 75, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=dJ46OIIsuHw

    // V45_EXPORT_BEGIN nid=CdUqp-LHLno
    [SysAbiExport(
        Nid = "CdUqp-LHLno",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi28ParameterToAddAndGetVariableD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0370(CpuContext ctx) => Destruct(ctx, 75);
    // V45_EXPORT_END nid=CdUqp-LHLno

    // V45_EXPORT_BEGIN nid=c7gIc2aHtZ8
    [SysAbiExport(
        Nid = "c7gIc2aHtZ8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi28ParameterToAddAndGetVariableD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0371(CpuContext ctx) => Destruct(ctx, 75);
    // V45_EXPORT_END nid=c7gIc2aHtZ8

    // V45_EXPORT_BEGIN nid=zq5zv1pV1So
    [SysAbiExport(
        Nid = "zq5zv1pV1So",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi37ParameterToDeleteMultiVariablesByUser17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0372(CpuContext ctx) => GetValue(ctx, 76, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=zq5zv1pV1So

    // V45_EXPORT_BEGIN nid=U8faoKjwEwY
    [SysAbiExport(
        Nid = "U8faoKjwEwY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi37ParameterToDeleteMultiVariablesByUser17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0373(CpuContext ctx) => SetValue(ctx, 76, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=U8faoKjwEwY

    // V45_EXPORT_BEGIN nid=ewaox0fh9DA
    [SysAbiExport(
        Nid = "ewaox0fh9DA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi37ParameterToDeleteMultiVariablesByUser19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0374(CpuContext ctx) => Unset(ctx, 76, 1);
    // V45_EXPORT_END nid=ewaox0fh9DA

    // V45_EXPORT_BEGIN nid=5toHmdcZrx4
    [SysAbiExport(
        Nid = "5toHmdcZrx4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi37ParameterToDeleteMultiVariablesByUserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0375(CpuContext ctx) => Destruct(ctx, 76);
    // V45_EXPORT_END nid=5toHmdcZrx4

    // V45_EXPORT_BEGIN nid=nVU6Ft6polI
    [SysAbiExport(
        Nid = "nVU6Ft6polI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi37ParameterToDeleteMultiVariablesByUserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0376(CpuContext ctx) => Destruct(ctx, 76);
    // V45_EXPORT_END nid=nVU6Ft6polI

    // V45_EXPORT_BEGIN nid=XSeRSYoExMM
    [SysAbiExport(
        Nid = "XSeRSYoExMM",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot8getlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0377(CpuContext ctx) => GetValue(ctx, 77, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=XSeRSYoExMM

    // V45_EXPORT_BEGIN nid=gbmNtW2A65o
    [SysAbiExport(
        Nid = "gbmNtW2A65o",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0378(CpuContext ctx) => GetValue(ctx, 77, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=gbmNtW2A65o

    // V45_EXPORT_BEGIN nid=QaEsQUw0ZYM
    [SysAbiExport(
        Nid = "QaEsQUw0ZYM",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot9getoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0379(CpuContext ctx) => GetValue(ctx, 77, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=QaEsQUw0ZYM

    // V45_EXPORT_BEGIN nid=JSXGe6gEhQM
    [SysAbiExport(
        Nid = "JSXGe6gEhQM",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0380(CpuContext ctx) => GetValue(ctx, 77, 4, ReturnKind.U32);
    // V45_EXPORT_END nid=JSXGe6gEhQM

    // V45_EXPORT_BEGIN nid=J3iduJTcpvQ
    [SysAbiExport(
        Nid = "J3iduJTcpvQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot8setlimitEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0381(CpuContext ctx) => SetValue(ctx, 77, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=J3iduJTcpvQ

    // V45_EXPORT_BEGIN nid=DJxQnDALoL0
    [SysAbiExport(
        Nid = "DJxQnDALoL0",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0382(CpuContext ctx) => SetValue(ctx, 77, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=DJxQnDALoL0

    // V45_EXPORT_BEGIN nid=QAXlroxEPKk
    [SysAbiExport(
        Nid = "QAXlroxEPKk",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot9setoffsetEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0383(CpuContext ctx) => SetValue(ctx, 77, 3, ValueSource.Register, false);
    // V45_EXPORT_END nid=QAXlroxEPKk

    // V45_EXPORT_BEGIN nid=Tq1oTpCqZq4
    [SysAbiExport(
        Nid = "Tq1oTpCqZq4",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0384(CpuContext ctx) => SetValue(ctx, 77, 4, ValueSource.Register, false);
    // V45_EXPORT_END nid=Tq1oTpCqZq4

    // V45_EXPORT_BEGIN nid=-Vp0aWV3ucY
    [SysAbiExport(
        Nid = "-Vp0aWV3ucY",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot10unsetlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0385(CpuContext ctx) => Unset(ctx, 77, 1);
    // V45_EXPORT_END nid=-Vp0aWV3ucY

    // V45_EXPORT_BEGIN nid=PEpsnLRM+s8
    [SysAbiExport(
        Nid = "PEpsnLRM+s8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0386(CpuContext ctx) => Unset(ctx, 77, 2);
    // V45_EXPORT_END nid=PEpsnLRM+s8

    // V45_EXPORT_BEGIN nid=F9a26lhcTpE
    [SysAbiExport(
        Nid = "F9a26lhcTpE",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlot11unsetoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0387(CpuContext ctx) => Unset(ctx, 77, 3);
    // V45_EXPORT_END nid=F9a26lhcTpE

    // V45_EXPORT_BEGIN nid=4btsnC+Eh7Q
    [SysAbiExport(
        Nid = "4btsnC+Eh7Q",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlotD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0388(CpuContext ctx) => Destruct(ctx, 77);
    // V45_EXPORT_END nid=4btsnC+Eh7Q

    // V45_EXPORT_BEGIN nid=wPO9107ThVw
    [SysAbiExport(
        Nid = "wPO9107ThVw",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesBySlotD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0389(CpuContext ctx) => Destruct(ctx, 77);
    // V45_EXPORT_END nid=wPO9107ThVw

    // V45_EXPORT_BEGIN nid=t1HNXigX3K0
    [SysAbiExport(
        Nid = "t1HNXigX3K0",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser8getlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0390(CpuContext ctx) => GetValue(ctx, 78, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=t1HNXigX3K0

    // V45_EXPORT_BEGIN nid=vK1sRvIOx1w
    [SysAbiExport(
        Nid = "vK1sRvIOx1w",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0391(CpuContext ctx) => GetValue(ctx, 78, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=vK1sRvIOx1w

    // V45_EXPORT_BEGIN nid=MJYvUugI8zs
    [SysAbiExport(
        Nid = "MJYvUugI8zs",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser9getoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0392(CpuContext ctx) => GetValue(ctx, 78, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=MJYvUugI8zs

    // V45_EXPORT_BEGIN nid=sbfbBFhDwAM
    [SysAbiExport(
        Nid = "sbfbBFhDwAM",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser8setlimitEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0393(CpuContext ctx) => SetValue(ctx, 78, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=sbfbBFhDwAM

    // V45_EXPORT_BEGIN nid=1-jw2YaVrug
    [SysAbiExport(
        Nid = "1-jw2YaVrug",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0394(CpuContext ctx) => SetValue(ctx, 78, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=1-jw2YaVrug

    // V45_EXPORT_BEGIN nid=G4QJQ2hZwWQ
    [SysAbiExport(
        Nid = "G4QJQ2hZwWQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser9setoffsetEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0395(CpuContext ctx) => SetValue(ctx, 78, 3, ValueSource.Register, false);
    // V45_EXPORT_END nid=G4QJQ2hZwWQ

    // V45_EXPORT_BEGIN nid=wkuuqGaR4CI
    [SysAbiExport(
        Nid = "wkuuqGaR4CI",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser10unsetlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0396(CpuContext ctx) => Unset(ctx, 78, 1);
    // V45_EXPORT_END nid=wkuuqGaR4CI

    // V45_EXPORT_BEGIN nid=lCxKxpEh+A8
    [SysAbiExport(
        Nid = "lCxKxpEh+A8",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0397(CpuContext ctx) => Unset(ctx, 78, 2);
    // V45_EXPORT_END nid=lCxKxpEh+A8

    // V45_EXPORT_BEGIN nid=kNCiQhdR4qA
    [SysAbiExport(
        Nid = "kNCiQhdR4qA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUser11unsetoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0398(CpuContext ctx) => Unset(ctx, 78, 3);
    // V45_EXPORT_END nid=kNCiQhdR4qA

    // V45_EXPORT_BEGIN nid=WH6fUUj9cAQ
    [SysAbiExport(
        Nid = "WH6fUUj9cAQ",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0399(CpuContext ctx) => Destruct(ctx, 78);
    // V45_EXPORT_END nid=WH6fUUj9cAQ

    // V45_EXPORT_BEGIN nid=yO88BZra7WA
    [SysAbiExport(
        Nid = "yO88BZra7WA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToGetMultiVariablesByUserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0400(CpuContext ctx) => Destruct(ctx, 78);
    // V45_EXPORT_END nid=yO88BZra7WA

    // V45_EXPORT_BEGIN nid=DoUT7MvPYhA
    [SysAbiExport(
        Nid = "DoUT7MvPYhA",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToSetMultiVariablesByUserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0401(CpuContext ctx) => Destruct(ctx, 79);
    // V45_EXPORT_END nid=DoUT7MvPYhA

    // V45_EXPORT_BEGIN nid=o-sMt4OM+Rc
    [SysAbiExport(
        Nid = "o-sMt4OM+Rc",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi34ParameterToSetMultiVariablesByUserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0402(CpuContext ctx) => Destruct(ctx, 79);
    // V45_EXPORT_END nid=o-sMt4OM+Rc

    // V45_EXPORT_BEGIN nid=UX-aM5jCHCQ
    [SysAbiExport(
        Nid = "UX-aM5jCHCQ",
        ExportName = "_ZNK3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi36ParameterToSetVariableWithConditions9getslotIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0403(CpuContext ctx) => GetValue(ctx, 80, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=UX-aM5jCHCQ

    // V45_EXPORT_BEGIN nid=UR2jculFawU
    [SysAbiExport(
        Nid = "UR2jculFawU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi36ParameterToSetVariableWithConditions9setslotIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0404(CpuContext ctx) => SetValue(ctx, 80, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=UR2jculFawU

    // V45_EXPORT_BEGIN nid=3xsbtd1XEbU
    [SysAbiExport(
        Nid = "3xsbtd1XEbU",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi36ParameterToSetVariableWithConditionsD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0405(CpuContext ctx) => Destruct(ctx, 80);
    // V45_EXPORT_END nid=3xsbtd1XEbU

    // V45_EXPORT_BEGIN nid=jAc86M302as
    [SysAbiExport(
        Nid = "jAc86M302as",
        ExportName = "_ZN3sce2Np9CppWebApi17TitleCloudStorage2V112VariablesApi36ParameterToSetVariableWithConditionsD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0406(CpuContext ctx) => Destruct(ctx, 80);
    // V45_EXPORT_END nid=jAc86M302as

    // V45_EXPORT_BEGIN nid=+bFVZHy54tw
    [SysAbiExport(
        Nid = "+bFVZHy54tw",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V16AvatarC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0407(CpuContext ctx) => Construct(ctx, 82);
    // V45_EXPORT_END nid=+bFVZHy54tw

    // V45_EXPORT_BEGIN nid=MNNHLFgBTWk
    [SysAbiExport(
        Nid = "MNNHLFgBTWk",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V16AvatarC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0408(CpuContext ctx) => Construct(ctx, 82);
    // V45_EXPORT_END nid=MNNHLFgBTWk

    // V45_EXPORT_BEGIN nid=EyWYVPvYnzg
    [SysAbiExport(
        Nid = "EyWYVPvYnzg",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V16AvatarD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0409(CpuContext ctx) => Destruct(ctx, 82);
    // V45_EXPORT_END nid=EyWYVPvYnzg

    // V45_EXPORT_BEGIN nid=UBuNTluTWOM
    [SysAbiExport(
        Nid = "UBuNTluTWOM",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V16AvatarD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0410(CpuContext ctx) => Destruct(ctx, 82);
    // V45_EXPORT_END nid=UBuNTluTWOM

    // V45_EXPORT_BEGIN nid=6lYJ-OpUyPs
    [SysAbiExport(
        Nid = "6lYJ-OpUyPs",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresenceC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0411(CpuContext ctx) => Construct(ctx, 84);
    // V45_EXPORT_END nid=6lYJ-OpUyPs

    // V45_EXPORT_BEGIN nid=yqvosp+aMWE
    [SysAbiExport(
        Nid = "yqvosp+aMWE",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresenceC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0412(CpuContext ctx) => Construct(ctx, 84);
    // V45_EXPORT_END nid=yqvosp+aMWE

    // V45_EXPORT_BEGIN nid=6Es3CbUEwQE
    [SysAbiExport(
        Nid = "6Es3CbUEwQE",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V113BasicPresence14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0413(CpuContext ctx) => IsSet(ctx, 84, 1);
    // V45_EXPORT_END nid=6Es3CbUEwQE

    // V45_EXPORT_BEGIN nid=Uc5eSnk3dvE
    [SysAbiExport(
        Nid = "Uc5eSnk3dvE",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V113BasicPresence12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0414(CpuContext ctx) => GetValue(ctx, 84, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=Uc5eSnk3dvE

    // V45_EXPORT_BEGIN nid=1bf+c7ebx0A
    [SysAbiExport(
        Nid = "1bf+c7ebx0A",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V113BasicPresence12getInContextEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0415(CpuContext ctx) => GetValue(ctx, 84, 2, ReturnKind.Bool);
    // V45_EXPORT_END nid=1bf+c7ebx0A

    // V45_EXPORT_BEGIN nid=OdIsrLAknok
    [SysAbiExport(
        Nid = "OdIsrLAknok",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V113BasicPresence14inContextIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0416(CpuContext ctx) => IsSet(ctx, 84, 2);
    // V45_EXPORT_END nid=OdIsrLAknok

    // V45_EXPORT_BEGIN nid=6bNZBfoPZwc
    [SysAbiExport(
        Nid = "6bNZBfoPZwc",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresence12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0417(CpuContext ctx) => SetValue(ctx, 84, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=6bNZBfoPZwc

    // V45_EXPORT_BEGIN nid=D5nSwhnZwM8
    [SysAbiExport(
        Nid = "D5nSwhnZwM8",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresence12setInContextERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0418(CpuContext ctx) => SetValue(ctx, 84, 2, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=D5nSwhnZwM8

    // V45_EXPORT_BEGIN nid=IRk2LD8KwS0
    [SysAbiExport(
        Nid = "IRk2LD8KwS0",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresence14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0419(CpuContext ctx) => Unset(ctx, 84, 1);
    // V45_EXPORT_END nid=IRk2LD8KwS0

    // V45_EXPORT_BEGIN nid=3crHndPLhWs
    [SysAbiExport(
        Nid = "3crHndPLhWs",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresence14unsetInContextEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0420(CpuContext ctx) => Unset(ctx, 84, 2);
    // V45_EXPORT_END nid=3crHndPLhWs

    // V45_EXPORT_BEGIN nid=7jv2iFyX20k
    [SysAbiExport(
        Nid = "7jv2iFyX20k",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresenceD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0421(CpuContext ctx) => Destruct(ctx, 84);
    // V45_EXPORT_END nid=7jv2iFyX20k

    // V45_EXPORT_BEGIN nid=r8b4fQiebU4
    [SysAbiExport(
        Nid = "r8b4fQiebU4",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113BasicPresenceD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0422(CpuContext ctx) => Destruct(ctx, 84);
    // V45_EXPORT_END nid=r8b4fQiebU4

    // V45_EXPORT_BEGIN nid=-TP5BT-FntM
    [SysAbiExport(
        Nid = "-TP5BT-FntM",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfileC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0423(CpuContext ctx) => Construct(ctx, 86);
    // V45_EXPORT_END nid=-TP5BT-FntM

    // V45_EXPORT_BEGIN nid=YBPm9rUjtYA
    [SysAbiExport(
        Nid = "YBPm9rUjtYA",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfileC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0424(CpuContext ctx) => Construct(ctx, 86);
    // V45_EXPORT_END nid=YBPm9rUjtYA

    // V45_EXPORT_BEGIN nid=E9R0IOdsZZw
    [SysAbiExport(
        Nid = "E9R0IOdsZZw",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V112BasicProfile14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0425(CpuContext ctx) => IsSet(ctx, 86, 1);
    // V45_EXPORT_END nid=E9R0IOdsZZw

    // V45_EXPORT_BEGIN nid=b9enc4+Xz6s
    [SysAbiExport(
        Nid = "b9enc4+Xz6s",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V112BasicProfile12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0426(CpuContext ctx) => GetValue(ctx, 86, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=b9enc4+Xz6s

    // V45_EXPORT_BEGIN nid=WCGKU7ZOFU4
    [SysAbiExport(
        Nid = "WCGKU7ZOFU4",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V112BasicProfile23getIsOfficiallyVerifiedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0427(CpuContext ctx) => GetValue(ctx, 86, 2, ReturnKind.Bool);
    // V45_EXPORT_END nid=WCGKU7ZOFU4

    // V45_EXPORT_BEGIN nid=6-RfgdMbM4k
    [SysAbiExport(
        Nid = "6-RfgdMbM4k",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V112BasicProfile25isOfficiallyVerifiedIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0428(CpuContext ctx) => IsSet(ctx, 86, 2);
    // V45_EXPORT_END nid=6-RfgdMbM4k

    // V45_EXPORT_BEGIN nid=eIRIcsSyhro
    [SysAbiExport(
        Nid = "eIRIcsSyhro",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfile12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0429(CpuContext ctx) => SetValue(ctx, 86, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=eIRIcsSyhro

    // V45_EXPORT_BEGIN nid=lUYELQFrN8E
    [SysAbiExport(
        Nid = "lUYELQFrN8E",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfile23setIsOfficiallyVerifiedERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0430(CpuContext ctx) => SetValue(ctx, 86, 2, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=lUYELQFrN8E

    // V45_EXPORT_BEGIN nid=CCmU-uYjeIk
    [SysAbiExport(
        Nid = "CCmU-uYjeIk",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfile14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0431(CpuContext ctx) => Unset(ctx, 86, 1);
    // V45_EXPORT_END nid=CCmU-uYjeIk

    // V45_EXPORT_BEGIN nid=Zj1BNXnzQcg
    [SysAbiExport(
        Nid = "Zj1BNXnzQcg",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfile25unsetIsOfficiallyVerifiedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0432(CpuContext ctx) => Unset(ctx, 86, 2);
    // V45_EXPORT_END nid=Zj1BNXnzQcg

    // V45_EXPORT_BEGIN nid=REt+k0TeaKo
    [SysAbiExport(
        Nid = "REt+k0TeaKo",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfileD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0433(CpuContext ctx) => Destruct(ctx, 86);
    // V45_EXPORT_END nid=REt+k0TeaKo

    // V45_EXPORT_BEGIN nid=rJX8As6nMrY
    [SysAbiExport(
        Nid = "rJX8As6nMrY",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V112BasicProfileD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0434(CpuContext ctx) => Destruct(ctx, 86);
    // V45_EXPORT_END nid=rJX8As6nMrY

    // V45_EXPORT_BEGIN nid=RphzLPLLB24
    [SysAbiExport(
        Nid = "RphzLPLLB24",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V115BasicProfileApi27ParameterToGetPublicProfileD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0435(CpuContext ctx) => Destruct(ctx, 87);
    // V45_EXPORT_END nid=RphzLPLLB24

    // V45_EXPORT_BEGIN nid=bVIEJr0rwsw
    [SysAbiExport(
        Nid = "bVIEJr0rwsw",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V115BasicProfileApi27ParameterToGetPublicProfileD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0436(CpuContext ctx) => Destruct(ctx, 87);
    // V45_EXPORT_END nid=bVIEJr0rwsw

    // V45_EXPORT_BEGIN nid=TZBK+iB67G0
    [SysAbiExport(
        Nid = "TZBK+iB67G0",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V115BasicProfileApi28ParameterToGetPublicProfilesD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0437(CpuContext ctx) => Destruct(ctx, 88);
    // V45_EXPORT_END nid=TZBK+iB67G0

    // V45_EXPORT_BEGIN nid=o7Rj82lRZ98
    [SysAbiExport(
        Nid = "o7Rj82lRZ98",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V115BasicProfileApi28ParameterToGetPublicProfilesD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0438(CpuContext ctx) => Destruct(ctx, 88);
    // V45_EXPORT_END nid=o7Rj82lRZ98

    // V45_EXPORT_BEGIN nid=af1dBuHUIhg
    [SysAbiExport(
        Nid = "af1dBuHUIhg",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsers8getlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0439(CpuContext ctx) => GetValue(ctx, 91, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=af1dBuHUIhg

    // V45_EXPORT_BEGIN nid=IGa9NHlyivY
    [SysAbiExport(
        Nid = "IGa9NHlyivY",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsers9getoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0440(CpuContext ctx) => GetValue(ctx, 91, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=IGa9NHlyivY

    // V45_EXPORT_BEGIN nid=us+hb1r9BN4
    [SysAbiExport(
        Nid = "us+hb1r9BN4",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsers8setlimitEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0441(CpuContext ctx) => SetValue(ctx, 91, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=us+hb1r9BN4

    // V45_EXPORT_BEGIN nid=wP-FIy-gRq0
    [SysAbiExport(
        Nid = "wP-FIy-gRq0",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsers9setoffsetEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0442(CpuContext ctx) => SetValue(ctx, 91, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=wP-FIy-gRq0

    // V45_EXPORT_BEGIN nid=IKtKACP9tMo
    [SysAbiExport(
        Nid = "IKtKACP9tMo",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsers10unsetlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0443(CpuContext ctx) => Unset(ctx, 91, 1);
    // V45_EXPORT_END nid=IKtKACP9tMo

    // V45_EXPORT_BEGIN nid=XMFJE+2zZIc
    [SysAbiExport(
        Nid = "XMFJE+2zZIc",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsers11unsetoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0444(CpuContext ctx) => Unset(ctx, 91, 2);
    // V45_EXPORT_END nid=XMFJE+2zZIc

    // V45_EXPORT_BEGIN nid=WFrVvA9uHU0
    [SysAbiExport(
        Nid = "WFrVvA9uHU0",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsersD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0445(CpuContext ctx) => Destruct(ctx, 91);
    // V45_EXPORT_END nid=WFrVvA9uHU0

    // V45_EXPORT_BEGIN nid=hj40eDtISJY
    [SysAbiExport(
        Nid = "hj40eDtISJY",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V19BlocksApi27ParameterToGetBlockingUsersD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0446(CpuContext ctx) => Destruct(ctx, 91);
    // V45_EXPORT_END nid=hj40eDtISJY

    // V45_EXPORT_BEGIN nid=J7DHUBI1l0I
    [SysAbiExport(
        Nid = "J7DHUBI1l0I",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V15ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0447(CpuContext ctx) => Construct(ctx, 93);
    // V45_EXPORT_END nid=J7DHUBI1l0I

    // V45_EXPORT_BEGIN nid=zr16QO3R4+0
    [SysAbiExport(
        Nid = "zr16QO3R4+0",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V15ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0448(CpuContext ctx) => Construct(ctx, 93);
    // V45_EXPORT_END nid=zr16QO3R4+0

    // V45_EXPORT_BEGIN nid=khKucrcspGQ
    [SysAbiExport(
        Nid = "khKucrcspGQ",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V15Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0449(CpuContext ctx) => GetValue(ctx, 93, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=khKucrcspGQ

    // V45_EXPORT_BEGIN nid=a-IN6rnSL1I
    [SysAbiExport(
        Nid = "a-IN6rnSL1I",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V15Error7setCodeERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0450(CpuContext ctx) => SetValue(ctx, 93, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=a-IN6rnSL1I

    // V45_EXPORT_BEGIN nid=2YSzwYnNE3Q
    [SysAbiExport(
        Nid = "2YSzwYnNE3Q",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V15ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0451(CpuContext ctx) => Destruct(ctx, 93);
    // V45_EXPORT_END nid=2YSzwYnNE3Q

    // V45_EXPORT_BEGIN nid=YBxUrFjgcQs
    [SysAbiExport(
        Nid = "YBxUrFjgcQs",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V15ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0452(CpuContext ctx) => Destruct(ctx, 93);
    // V45_EXPORT_END nid=YBxUrFjgcQs

    // V45_EXPORT_BEGIN nid=-o2tjjIdsr8
    [SysAbiExport(
        Nid = "-o2tjjIdsr8",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113ErrorResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0453(CpuContext ctx) => Construct(ctx, 95);
    // V45_EXPORT_END nid=-o2tjjIdsr8

    // V45_EXPORT_BEGIN nid=ojqFf7axj3A
    [SysAbiExport(
        Nid = "ojqFf7axj3A",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113ErrorResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0454(CpuContext ctx) => Construct(ctx, 95);
    // V45_EXPORT_END nid=ojqFf7axj3A

    // V45_EXPORT_BEGIN nid=6RO+OfAxKM8
    [SysAbiExport(
        Nid = "6RO+OfAxKM8",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113ErrorResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0455(CpuContext ctx) => Destruct(ctx, 95);
    // V45_EXPORT_END nid=6RO+OfAxKM8

    // V45_EXPORT_BEGIN nid=sPAcal3M8SY
    [SysAbiExport(
        Nid = "sPAcal3M8SY",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V113ErrorResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0456(CpuContext ctx) => Destruct(ctx, 95);
    // V45_EXPORT_END nid=sPAcal3M8SY

    // V45_EXPORT_BEGIN nid=mA9-3pYGy08
    [SysAbiExport(
        Nid = "mA9-3pYGy08",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriends8getlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0457(CpuContext ctx) => GetValue(ctx, 97, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=mA9-3pYGy08

    // V45_EXPORT_BEGIN nid=aHG7WPzIkss
    [SysAbiExport(
        Nid = "aHG7WPzIkss",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriends9getoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0458(CpuContext ctx) => GetValue(ctx, 97, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=aHG7WPzIkss

    // V45_EXPORT_BEGIN nid=k7+6XfiVmCw
    [SysAbiExport(
        Nid = "k7+6XfiVmCw",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriends8setlimitEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0459(CpuContext ctx) => SetValue(ctx, 97, 1, ValueSource.Register, false);
    // V45_EXPORT_END nid=k7+6XfiVmCw

    // V45_EXPORT_BEGIN nid=F6g64Yst1FQ
    [SysAbiExport(
        Nid = "F6g64Yst1FQ",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriends9setoffsetEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0460(CpuContext ctx) => SetValue(ctx, 97, 2, ValueSource.Register, false);
    // V45_EXPORT_END nid=F6g64Yst1FQ

    // V45_EXPORT_BEGIN nid=oYcDkClOA8U
    [SysAbiExport(
        Nid = "oYcDkClOA8U",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriends10unsetlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0461(CpuContext ctx) => Unset(ctx, 97, 1);
    // V45_EXPORT_END nid=oYcDkClOA8U

    // V45_EXPORT_BEGIN nid=NInMZRpAc3g
    [SysAbiExport(
        Nid = "NInMZRpAc3g",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriends11unsetoffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0462(CpuContext ctx) => Unset(ctx, 97, 2);
    // V45_EXPORT_END nid=NInMZRpAc3g

    // V45_EXPORT_BEGIN nid=FwZxHpDJ0gs
    [SysAbiExport(
        Nid = "FwZxHpDJ0gs",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriendsD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0463(CpuContext ctx) => Destruct(ctx, 97);
    // V45_EXPORT_END nid=FwZxHpDJ0gs

    // V45_EXPORT_BEGIN nid=ZdVlyQI3f-c
    [SysAbiExport(
        Nid = "ZdVlyQI3f-c",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V110FriendsApi21ParameterToGetFriendsD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0464(CpuContext ctx) => Destruct(ctx, 97);
    // V45_EXPORT_END nid=ZdVlyQI3f-c

    // V45_EXPORT_BEGIN nid=EO+sWh4e9Rc
    [SysAbiExport(
        Nid = "EO+sWh4e9Rc",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetBasicPresencesResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0465(CpuContext ctx) => Construct(ctx, 99);
    // V45_EXPORT_END nid=EO+sWh4e9Rc

    // V45_EXPORT_BEGIN nid=ZLHIMOYVWWE
    [SysAbiExport(
        Nid = "ZLHIMOYVWWE",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetBasicPresencesResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0466(CpuContext ctx) => Construct(ctx, 99);
    // V45_EXPORT_END nid=ZLHIMOYVWWE

    // V45_EXPORT_BEGIN nid=C3KUJDxz-is
    [SysAbiExport(
        Nid = "C3KUJDxz-is",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetBasicPresencesResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0467(CpuContext ctx) => Destruct(ctx, 99);
    // V45_EXPORT_END nid=C3KUJDxz-is

    // V45_EXPORT_BEGIN nid=y0BpcQP1nto
    [SysAbiExport(
        Nid = "y0BpcQP1nto",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetBasicPresencesResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0468(CpuContext ctx) => Destruct(ctx, 99);
    // V45_EXPORT_END nid=y0BpcQP1nto

    // V45_EXPORT_BEGIN nid=XKe-AxbD9No
    [SysAbiExport(
        Nid = "XKe-AxbD9No",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0469(CpuContext ctx) => Construct(ctx, 101);
    // V45_EXPORT_END nid=XKe-AxbD9No

    // V45_EXPORT_BEGIN nid=p7DQObtV1sg
    [SysAbiExport(
        Nid = "p7DQObtV1sg",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0470(CpuContext ctx) => Construct(ctx, 101);
    // V45_EXPORT_END nid=p7DQObtV1sg

    // V45_EXPORT_BEGIN nid=8qYmcJgmz70
    [SysAbiExport(
        Nid = "8qYmcJgmz70",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse13getNextOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0471(CpuContext ctx) => GetValue(ctx, 101, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=8qYmcJgmz70

    // V45_EXPORT_BEGIN nid=8xtAsAizlvE
    [SysAbiExport(
        Nid = "8xtAsAizlvE",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse17getPreviousOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0472(CpuContext ctx) => GetValue(ctx, 101, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=8xtAsAizlvE

    // V45_EXPORT_BEGIN nid=TnEmXni08qk
    [SysAbiExport(
        Nid = "TnEmXni08qk",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse17getTotalItemCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0473(CpuContext ctx) => GetValue(ctx, 101, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=TnEmXni08qk

    // V45_EXPORT_BEGIN nid=jxn875wvWPY
    [SysAbiExport(
        Nid = "jxn875wvWPY",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse15nextOffsetIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0474(CpuContext ctx) => IsSet(ctx, 101, 1);
    // V45_EXPORT_END nid=jxn875wvWPY

    // V45_EXPORT_BEGIN nid=u1BIPLpvRLo
    [SysAbiExport(
        Nid = "u1BIPLpvRLo",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse19previousOffsetIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0475(CpuContext ctx) => IsSet(ctx, 101, 2);
    // V45_EXPORT_END nid=u1BIPLpvRLo

    // V45_EXPORT_BEGIN nid=80Oq9-9fvGM
    [SysAbiExport(
        Nid = "80Oq9-9fvGM",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse13setNextOffsetERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0476(CpuContext ctx) => SetValue(ctx, 101, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=80Oq9-9fvGM

    // V45_EXPORT_BEGIN nid=XQTth-+arz8
    [SysAbiExport(
        Nid = "XQTth-+arz8",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse17setPreviousOffsetERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0477(CpuContext ctx) => SetValue(ctx, 101, 2, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=XQTth-+arz8

    // V45_EXPORT_BEGIN nid=hHbHdXvH5NI
    [SysAbiExport(
        Nid = "hHbHdXvH5NI",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse17setTotalItemCountERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0478(CpuContext ctx) => SetValue(ctx, 101, 3, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=hHbHdXvH5NI

    // V45_EXPORT_BEGIN nid=Ytxk0PHZaWE
    [SysAbiExport(
        Nid = "Ytxk0PHZaWE",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse15unsetNextOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0479(CpuContext ctx) => Unset(ctx, 101, 1);
    // V45_EXPORT_END nid=Ytxk0PHZaWE

    // V45_EXPORT_BEGIN nid=c9d+u6qY1Vw
    [SysAbiExport(
        Nid = "c9d+u6qY1Vw",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponse19unsetPreviousOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0480(CpuContext ctx) => Unset(ctx, 101, 2);
    // V45_EXPORT_END nid=c9d+u6qY1Vw

    // V45_EXPORT_BEGIN nid=1Q7JNd9NM1o
    [SysAbiExport(
        Nid = "1Q7JNd9NM1o",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0481(CpuContext ctx) => Destruct(ctx, 101);
    // V45_EXPORT_END nid=1Q7JNd9NM1o

    // V45_EXPORT_BEGIN nid=tgoE87ZlQTo
    [SysAbiExport(
        Nid = "tgoE87ZlQTo",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetBlockingUsersResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0482(CpuContext ctx) => Destruct(ctx, 101);
    // V45_EXPORT_END nid=tgoE87ZlQTo

    // V45_EXPORT_BEGIN nid=1PGe55Cm1qI
    [SysAbiExport(
        Nid = "1PGe55Cm1qI",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0483(CpuContext ctx) => Construct(ctx, 103);
    // V45_EXPORT_END nid=1PGe55Cm1qI

    // V45_EXPORT_BEGIN nid=t3rfBQmc4sY
    [SysAbiExport(
        Nid = "t3rfBQmc4sY",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0484(CpuContext ctx) => Construct(ctx, 103);
    // V45_EXPORT_END nid=t3rfBQmc4sY

    // V45_EXPORT_BEGIN nid=GKHM54nGcrE
    [SysAbiExport(
        Nid = "GKHM54nGcrE",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse13getNextOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0485(CpuContext ctx) => GetValue(ctx, 103, 1, ReturnKind.U32);
    // V45_EXPORT_END nid=GKHM54nGcrE

    // V45_EXPORT_BEGIN nid=Rg9KCjkElx4
    [SysAbiExport(
        Nid = "Rg9KCjkElx4",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse17getPreviousOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0486(CpuContext ctx) => GetValue(ctx, 103, 2, ReturnKind.U32);
    // V45_EXPORT_END nid=Rg9KCjkElx4

    // V45_EXPORT_BEGIN nid=5zM0S8rA1Cs
    [SysAbiExport(
        Nid = "5zM0S8rA1Cs",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse17getTotalItemCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0487(CpuContext ctx) => GetValue(ctx, 103, 3, ReturnKind.U32);
    // V45_EXPORT_END nid=5zM0S8rA1Cs

    // V45_EXPORT_BEGIN nid=yH83vkJ7cEY
    [SysAbiExport(
        Nid = "yH83vkJ7cEY",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse15nextOffsetIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0488(CpuContext ctx) => IsSet(ctx, 103, 1);
    // V45_EXPORT_END nid=yH83vkJ7cEY

    // V45_EXPORT_BEGIN nid=6jdNCEi6cFI
    [SysAbiExport(
        Nid = "6jdNCEi6cFI",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse19previousOffsetIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0489(CpuContext ctx) => IsSet(ctx, 103, 2);
    // V45_EXPORT_END nid=6jdNCEi6cFI

    // V45_EXPORT_BEGIN nid=o787qsGwSJs
    [SysAbiExport(
        Nid = "o787qsGwSJs",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse13setNextOffsetERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0490(CpuContext ctx) => SetValue(ctx, 103, 1, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=o787qsGwSJs

    // V45_EXPORT_BEGIN nid=JQ0sop7jsm4
    [SysAbiExport(
        Nid = "JQ0sop7jsm4",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse17setPreviousOffsetERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0491(CpuContext ctx) => SetValue(ctx, 103, 2, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=JQ0sop7jsm4

    // V45_EXPORT_BEGIN nid=AdhbdaLsiik
    [SysAbiExport(
        Nid = "AdhbdaLsiik",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse17setTotalItemCountERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0492(CpuContext ctx) => SetValue(ctx, 103, 3, ValueSource.U32Ref, false);
    // V45_EXPORT_END nid=AdhbdaLsiik

    // V45_EXPORT_BEGIN nid=k5YhL+P3rJ8
    [SysAbiExport(
        Nid = "k5YhL+P3rJ8",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse19totalItemCountIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0493(CpuContext ctx) => IsSet(ctx, 103, 3);
    // V45_EXPORT_END nid=k5YhL+P3rJ8

    // V45_EXPORT_BEGIN nid=i3rOwm9Ztbw
    [SysAbiExport(
        Nid = "i3rOwm9Ztbw",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse15unsetNextOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0494(CpuContext ctx) => Unset(ctx, 103, 1);
    // V45_EXPORT_END nid=i3rOwm9Ztbw

    // V45_EXPORT_BEGIN nid=0rNzyiMSRvI
    [SysAbiExport(
        Nid = "0rNzyiMSRvI",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse19unsetPreviousOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0495(CpuContext ctx) => Unset(ctx, 103, 2);
    // V45_EXPORT_END nid=0rNzyiMSRvI

    // V45_EXPORT_BEGIN nid=lqye4eoi5nI
    [SysAbiExport(
        Nid = "lqye4eoi5nI",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponse19unsetTotalItemCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0496(CpuContext ctx) => Unset(ctx, 103, 3);
    // V45_EXPORT_END nid=lqye4eoi5nI

    // V45_EXPORT_BEGIN nid=E1VALdavf1k
    [SysAbiExport(
        Nid = "E1VALdavf1k",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0497(CpuContext ctx) => Destruct(ctx, 103);
    // V45_EXPORT_END nid=E1VALdavf1k

    // V45_EXPORT_BEGIN nid=eFOrN+nZ1kg
    [SysAbiExport(
        Nid = "eFOrN+nZ1kg",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V118GetFriendsResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0498(CpuContext ctx) => Destruct(ctx, 103);
    // V45_EXPORT_END nid=eFOrN+nZ1kg

    // V45_EXPORT_BEGIN nid=a0Zj1cVYuHQ
    [SysAbiExport(
        Nid = "a0Zj1cVYuHQ",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0499(CpuContext ctx) => Construct(ctx, 105);
    // V45_EXPORT_END nid=a0Zj1cVYuHQ

    // V45_EXPORT_BEGIN nid=afBzbtb04ZQ
    [SysAbiExport(
        Nid = "afBzbtb04ZQ",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0500(CpuContext ctx) => Construct(ctx, 105);
    // V45_EXPORT_END nid=afBzbtb04ZQ

    // V45_EXPORT_BEGIN nid=gAvF0fPDITg
    [SysAbiExport(
        Nid = "gAvF0fPDITg",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponse14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0501(CpuContext ctx) => IsSet(ctx, 105, 1);
    // V45_EXPORT_END nid=gAvF0fPDITg

    // V45_EXPORT_BEGIN nid=UXRgSH83N9Y
    [SysAbiExport(
        Nid = "UXRgSH83N9Y",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponse12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0502(CpuContext ctx) => GetValue(ctx, 105, 1, ReturnKind.U64);
    // V45_EXPORT_END nid=UXRgSH83N9Y

    // V45_EXPORT_BEGIN nid=tDBjxghgDXc
    [SysAbiExport(
        Nid = "tDBjxghgDXc",
        ExportName = "_ZNK3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponse23getIsOfficiallyVerifiedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0503(CpuContext ctx) => GetValue(ctx, 105, 2, ReturnKind.Bool);
    // V45_EXPORT_END nid=tDBjxghgDXc

    // V45_EXPORT_BEGIN nid=+k8qx70PRSQ
    [SysAbiExport(
        Nid = "+k8qx70PRSQ",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponse12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0504(CpuContext ctx) => SetValue(ctx, 105, 1, ValueSource.U64Ref, false);
    // V45_EXPORT_END nid=+k8qx70PRSQ

    // V45_EXPORT_BEGIN nid=hb289atcuLE
    [SysAbiExport(
        Nid = "hb289atcuLE",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponse23setIsOfficiallyVerifiedERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0505(CpuContext ctx) => SetValue(ctx, 105, 2, ValueSource.U8Ref, true);
    // V45_EXPORT_END nid=hb289atcuLE

    // V45_EXPORT_BEGIN nid=hHQ9kdZrHYc
    [SysAbiExport(
        Nid = "hHQ9kdZrHYc",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponse14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0506(CpuContext ctx) => Unset(ctx, 105, 1);
    // V45_EXPORT_END nid=hHQ9kdZrHYc

    // V45_EXPORT_BEGIN nid=1uvFpFqye9g
    [SysAbiExport(
        Nid = "1uvFpFqye9g",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0507(CpuContext ctx) => Destruct(ctx, 105);
    // V45_EXPORT_END nid=1uvFpFqye9g

    // V45_EXPORT_BEGIN nid=GCDXjCEnKck
    [SysAbiExport(
        Nid = "GCDXjCEnKck",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V124GetPublicProfileResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0508(CpuContext ctx) => Destruct(ctx, 105);
    // V45_EXPORT_END nid=GCDXjCEnKck

    // V45_EXPORT_BEGIN nid=4jLxGyUym+Y
    [SysAbiExport(
        Nid = "4jLxGyUym+Y",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetPublicProfilesResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0509(CpuContext ctx) => Construct(ctx, 107);
    // V45_EXPORT_END nid=4jLxGyUym+Y

    // V45_EXPORT_BEGIN nid=bjJTJ2G5VIA
    [SysAbiExport(
        Nid = "bjJTJ2G5VIA",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetPublicProfilesResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0510(CpuContext ctx) => Construct(ctx, 107);
    // V45_EXPORT_END nid=bjJTJ2G5VIA

    // V45_EXPORT_BEGIN nid=EdTr7I4K1uI
    [SysAbiExport(
        Nid = "EdTr7I4K1uI",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetPublicProfilesResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0511(CpuContext ctx) => Destruct(ctx, 107);
    // V45_EXPORT_END nid=EdTr7I4K1uI

    // V45_EXPORT_BEGIN nid=J9ZSTc1O0MM
    [SysAbiExport(
        Nid = "J9ZSTc1O0MM",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V125GetPublicProfilesResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0512(CpuContext ctx) => Destruct(ctx, 107);
    // V45_EXPORT_END nid=J9ZSTc1O0MM

    // V45_EXPORT_BEGIN nid=USxp2eW0eLE
    [SysAbiExport(
        Nid = "USxp2eW0eLE",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V114PersonalDetailC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0513(CpuContext ctx) => Construct(ctx, 109);
    // V45_EXPORT_END nid=USxp2eW0eLE

    // V45_EXPORT_BEGIN nid=oYZoqxL-hH0
    [SysAbiExport(
        Nid = "oYZoqxL-hH0",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V114PersonalDetailC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0514(CpuContext ctx) => Construct(ctx, 109);
    // V45_EXPORT_END nid=oYZoqxL-hH0

    // V45_EXPORT_BEGIN nid=1iTehbdJsN4
    [SysAbiExport(
        Nid = "1iTehbdJsN4",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V114PersonalDetailD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0515(CpuContext ctx) => Destruct(ctx, 109);
    // V45_EXPORT_END nid=1iTehbdJsN4

    // V45_EXPORT_BEGIN nid=OIp5AZlyjEc
    [SysAbiExport(
        Nid = "OIp5AZlyjEc",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V114PersonalDetailD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0516(CpuContext ctx) => Destruct(ctx, 109);
    // V45_EXPORT_END nid=OIp5AZlyjEc

    // V45_EXPORT_BEGIN nid=Xq-82jMGxFM
    [SysAbiExport(
        Nid = "Xq-82jMGxFM",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V111PresenceApi28ParameterToGetBasicPresencesD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0517(CpuContext ctx) => Destruct(ctx, 111);
    // V45_EXPORT_END nid=Xq-82jMGxFM

    // V45_EXPORT_BEGIN nid=pDUQVO32lZY
    [SysAbiExport(
        Nid = "pDUQVO32lZY",
        ExportName = "_ZN3sce2Np9CppWebApi11UserProfile2V111PresenceApi28ParameterToGetBasicPresencesD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V45Service0518(CpuContext ctx) => Destruct(ctx, 111);
    // V45_EXPORT_END nid=pDUQVO32lZY

}
