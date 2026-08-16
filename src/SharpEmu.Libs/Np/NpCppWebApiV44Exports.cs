// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Np;

public static class NpCppWebApiV44Exports
{
    // V44: deterministic local NP CppWebApi service-model compatibility batch.
    // Remote NP/WebApi operations, JSON object layout, factories and non-trivial
    // C++ containers remain intentionally blocked by the package manifest.
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
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
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

    private static int SetValue(
        CpuContext ctx,
        int typeId,
        int fieldId,
        ValueSource source,
        bool normalizeBool)
    {
        var address = ctx[CpuRegister.Rdi];
        if (address == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        ulong raw;
        switch (source)
        {
            case ValueSource.U8Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 1, out raw))
                {
                    return (int)OrbisGen2Result.ORBIS_GEN2_OK;
                }
                break;
            case ValueSource.U16Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 2, out raw))
                {
                    return (int)OrbisGen2Result.ORBIS_GEN2_OK;
                }
                break;
            case ValueSource.U32Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 4, out raw))
                {
                    return (int)OrbisGen2Result.ORBIS_GEN2_OK;
                }
                break;
            case ValueSource.U64Ref:
                if (!TryReadUnsigned(ctx, ctx[CpuRegister.Rsi], 8, out raw))
                {
                    return (int)OrbisGen2Result.ORBIS_GEN2_OK;
                }
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
                return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        if (normalizeBool)
        {
            raw = raw == 0 ? 0UL : 1UL;
        }

        var state = GetOrCreateState(ctx, address, typeId);
        lock (state.Gate)
        {
            state.Fields[fieldId] = raw;
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int GetValue(CpuContext ctx, int typeId, int fieldId, ReturnKind kind)
    {
        ulong raw = 0;
        var state = TryGetState(ctx, ctx[CpuRegister.Rdi], typeId);
        if (state is not null)
        {
            lock (state.Gate)
            {
                _ = state.Fields.TryGetValue(fieldId, out raw);
            }
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
            {
                result = state.Fields.ContainsKey(fieldId);
            }
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
            {
                _ = state.Fields.Remove(fieldId);
            }
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    // V44_EXPORT_BEGIN nid=4W0fAoG50Nk
    [SysAbiExport(
        Nid = "4W0fAoG50Nk",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRatingC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0001(CpuContext ctx) => Construct(ctx, 1);
    // V44_EXPORT_END nid=4W0fAoG50Nk

    // V44_EXPORT_BEGIN nid=KHXsXc9VSzY
    [SysAbiExport(
        Nid = "KHXsXc9VSzY",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRatingC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0002(CpuContext ctx) => Construct(ctx, 1);
    // V44_EXPORT_END nid=KHXsXc9VSzY

    // V44_EXPORT_BEGIN nid=bqO+QMNSTD8
    [SysAbiExport(
        Nid = "bqO+QMNSTD8",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0006(CpuContext ctx) => GetValue(ctx, 1, 1, ReturnKind.Float32);
    // V44_EXPORT_END nid=bqO+QMNSTD8

    // V44_EXPORT_BEGIN nid=xWZkfYm5LDY
    [SysAbiExport(
        Nid = "xWZkfYm5LDY",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating8getTotalEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0007(CpuContext ctx) => GetValue(ctx, 1, 2, ReturnKind.U32);
    // V44_EXPORT_END nid=xWZkfYm5LDY

    // V44_EXPORT_BEGIN nid=0YSSzw0gloY
    [SysAbiExport(
        Nid = "0YSSzw0gloY",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating10scoreIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0008(CpuContext ctx) => IsSet(ctx, 1, 1);
    // V44_EXPORT_END nid=0YSSzw0gloY

    // V44_EXPORT_BEGIN nid=F-zFpvJdGSc
    [SysAbiExport(
        Nid = "F-zFpvJdGSc",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating8setScoreERKf",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0010(CpuContext ctx) => SetValue(ctx, 1, 1, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=F-zFpvJdGSc

    // V44_EXPORT_BEGIN nid=1hhDlnY9NRw
    [SysAbiExport(
        Nid = "1hhDlnY9NRw",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating8setTotalERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0011(CpuContext ctx) => SetValue(ctx, 1, 2, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=1hhDlnY9NRw

    // V44_EXPORT_BEGIN nid=H4ynxwcDMGg
    [SysAbiExport(
        Nid = "H4ynxwcDMGg",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating10totalIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0013(CpuContext ctx) => IsSet(ctx, 1, 2);
    // V44_EXPORT_END nid=H4ynxwcDMGg

    // V44_EXPORT_BEGIN nid=Y5YAhR330PU
    [SysAbiExport(
        Nid = "Y5YAhR330PU",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating10unsetScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0015(CpuContext ctx) => Unset(ctx, 1, 1);
    // V44_EXPORT_END nid=Y5YAhR330PU

    // V44_EXPORT_BEGIN nid=D1N2bsTVWFo
    [SysAbiExport(
        Nid = "D1N2bsTVWFo",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRating10unsetTotalEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0016(CpuContext ctx) => Unset(ctx, 1, 2);
    // V44_EXPORT_END nid=D1N2bsTVWFo

    // V44_EXPORT_BEGIN nid=-cygyY78b5A
    [SysAbiExport(
        Nid = "-cygyY78b5A",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRatingD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0017(CpuContext ctx) => Destruct(ctx, 1);
    // V44_EXPORT_END nid=-cygyY78b5A

    // V44_EXPORT_BEGIN nid=kF85XyAhZiU
    [SysAbiExport(
        Nid = "kF85XyAhZiU",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V515ContainerRatingD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0018(CpuContext ctx) => Destruct(ctx, 1);
    // V44_EXPORT_END nid=kF85XyAhZiU

    // V44_EXPORT_BEGIN nid=3tnX4BYslaY
    [SysAbiExport(
        Nid = "3tnX4BYslaY",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCountC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0019(CpuContext ctx) => Construct(ctx, 2);
    // V44_EXPORT_END nid=3tnX4BYslaY

    // V44_EXPORT_BEGIN nid=QI10G7iFT6s
    [SysAbiExport(
        Nid = "QI10G7iFT6s",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCountC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0020(CpuContext ctx) => Construct(ctx, 2);
    // V44_EXPORT_END nid=QI10G7iFT6s

    // V44_EXPORT_BEGIN nid=OgIbLp+FJ2I
    [SysAbiExport(
        Nid = "OgIbLp+FJ2I",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount10countIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0021(CpuContext ctx) => IsSet(ctx, 2, 3);
    // V44_EXPORT_END nid=OgIbLp+FJ2I

    // V44_EXPORT_BEGIN nid=GV4t+Ojz4UE
    [SysAbiExport(
        Nid = "GV4t+Ojz4UE",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount8getCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0023(CpuContext ctx) => GetValue(ctx, 2, 3, ReturnKind.U32);
    // V44_EXPORT_END nid=GV4t+Ojz4UE

    // V44_EXPORT_BEGIN nid=yfbbzRuWWJA
    [SysAbiExport(
        Nid = "yfbbzRuWWJA",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0024(CpuContext ctx) => GetValue(ctx, 2, 4, ReturnKind.U32);
    // V44_EXPORT_END nid=yfbbzRuWWJA

    // V44_EXPORT_BEGIN nid=eKQk89XMt3g
    [SysAbiExport(
        Nid = "eKQk89XMt3g",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount10scoreIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0025(CpuContext ctx) => IsSet(ctx, 2, 4);
    // V44_EXPORT_END nid=eKQk89XMt3g

    // V44_EXPORT_BEGIN nid=twGVBYdKbMg
    [SysAbiExport(
        Nid = "twGVBYdKbMg",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount8setCountERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0026(CpuContext ctx) => SetValue(ctx, 2, 3, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=twGVBYdKbMg

    // V44_EXPORT_BEGIN nid=oh2WU6fkK9Q
    [SysAbiExport(
        Nid = "oh2WU6fkK9Q",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount8setScoreERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0027(CpuContext ctx) => SetValue(ctx, 2, 4, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=oh2WU6fkK9Q

    // V44_EXPORT_BEGIN nid=WGzXiFzpXQQ
    [SysAbiExport(
        Nid = "WGzXiFzpXQQ",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount10unsetCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0029(CpuContext ctx) => Unset(ctx, 2, 3);
    // V44_EXPORT_END nid=WGzXiFzpXQQ

    // V44_EXPORT_BEGIN nid=2H7XUKtHAdc
    [SysAbiExport(
        Nid = "2H7XUKtHAdc",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCount10unsetScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0030(CpuContext ctx) => Unset(ctx, 2, 4);
    // V44_EXPORT_END nid=2H7XUKtHAdc

    // V44_EXPORT_BEGIN nid=H9V5-dRsnXI
    [SysAbiExport(
        Nid = "H9V5-dRsnXI",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCountD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0031(CpuContext ctx) => Destruct(ctx, 2);
    // V44_EXPORT_END nid=H9V5-dRsnXI

    // V44_EXPORT_BEGIN nid=JPz5ZejS4k8
    [SysAbiExport(
        Nid = "JPz5ZejS4k8",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V520ContainerRatingCountD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0032(CpuContext ctx) => Destruct(ctx, 2);
    // V44_EXPORT_END nid=JPz5ZejS4k8

    // V44_EXPORT_BEGIN nid=IFH02-MW68w
    [SysAbiExport(
        Nid = "IFH02-MW68w",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V55ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0086(CpuContext ctx) => Construct(ctx, 3);
    // V44_EXPORT_END nid=IFH02-MW68w

    // V44_EXPORT_BEGIN nid=XgSP7YfpXs4
    [SysAbiExport(
        Nid = "XgSP7YfpXs4",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V55ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0087(CpuContext ctx) => Construct(ctx, 3);
    // V44_EXPORT_END nid=XgSP7YfpXs4

    // V44_EXPORT_BEGIN nid=MnqoHt0rzQ0
    [SysAbiExport(
        Nid = "MnqoHt0rzQ0",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V55Error9codeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0088(CpuContext ctx) => IsSet(ctx, 3, 5);
    // V44_EXPORT_END nid=MnqoHt0rzQ0

    // V44_EXPORT_BEGIN nid=SFkKVDcl0ww
    [SysAbiExport(
        Nid = "SFkKVDcl0ww",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V55Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0090(CpuContext ctx) => GetValue(ctx, 3, 5, ReturnKind.U32);
    // V44_EXPORT_END nid=SFkKVDcl0ww

    // V44_EXPORT_BEGIN nid=+Ly9G7OxvE8
    [SysAbiExport(
        Nid = "+Ly9G7OxvE8",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V55Error7setCodeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0098(CpuContext ctx) => SetValue(ctx, 3, 5, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=+Ly9G7OxvE8

    // V44_EXPORT_BEGIN nid=3O-VCkQL+w8
    [SysAbiExport(
        Nid = "3O-VCkQL+w8",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V55Error9unsetCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0105(CpuContext ctx) => Unset(ctx, 3, 5);
    // V44_EXPORT_END nid=3O-VCkQL+w8

    // V44_EXPORT_BEGIN nid=V4-iHxwpOM0
    [SysAbiExport(
        Nid = "V4-iHxwpOM0",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V55ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0110(CpuContext ctx) => Destruct(ctx, 3);
    // V44_EXPORT_END nid=V4-iHxwpOM0

    // V44_EXPORT_BEGIN nid=Z0VNyGEdSKk
    [SysAbiExport(
        Nid = "Z0VNyGEdSKk",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V55ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0111(CpuContext ctx) => Destruct(ctx, 3);
    // V44_EXPORT_END nid=Z0VNyGEdSKk

    // V44_EXPORT_BEGIN nid=C28sII4CaLQ
    [SysAbiExport(
        Nid = "C28sII4CaLQ",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57ProductC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0147(CpuContext ctx) => Construct(ctx, 4);
    // V44_EXPORT_END nid=C28sII4CaLQ

    // V44_EXPORT_BEGIN nid=DHOTYcqa4hk
    [SysAbiExport(
        Nid = "DHOTYcqa4hk",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57ProductC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0148(CpuContext ctx) => Construct(ctx, 4);
    // V44_EXPORT_END nid=DHOTYcqa4hk

    // V44_EXPORT_BEGIN nid=rjXWL1hs2qg
    [SysAbiExport(
        Nid = "rjXWL1hs2qg",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V57Product13ageLimitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0149(CpuContext ctx) => IsSet(ctx, 4, 6);
    // V44_EXPORT_END nid=rjXWL1hs2qg

    // V44_EXPORT_BEGIN nid=C-IAF74xKYg
    [SysAbiExport(
        Nid = "C-IAF74xKYg",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V57Product11getAgeLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0156(CpuContext ctx) => GetValue(ctx, 4, 6, ReturnKind.U32);
    // V44_EXPORT_END nid=C-IAF74xKYg

    // V44_EXPORT_BEGIN nid=Gr7RF3--uDc
    [SysAbiExport(
        Nid = "Gr7RF3--uDc",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V57Product10getVersionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0172(CpuContext ctx) => GetValue(ctx, 4, 7, ReturnKind.U32);
    // V44_EXPORT_END nid=Gr7RF3--uDc

    // V44_EXPORT_BEGIN nid=MoEXecwSGLk
    [SysAbiExport(
        Nid = "MoEXecwSGLk",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57Product11setAgeLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0179(CpuContext ctx) => SetValue(ctx, 4, 6, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=MoEXecwSGLk

    // V44_EXPORT_BEGIN nid=h1Z1bwr5Aas
    [SysAbiExport(
        Nid = "h1Z1bwr5Aas",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57Product10setVersionERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0195(CpuContext ctx) => SetValue(ctx, 4, 7, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=h1Z1bwr5Aas

    // V44_EXPORT_BEGIN nid=NizpTB4K3bs
    [SysAbiExport(
        Nid = "NizpTB4K3bs",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57Product13unsetAgeLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0198(CpuContext ctx) => Unset(ctx, 4, 6);
    // V44_EXPORT_END nid=NizpTB4K3bs

    // V44_EXPORT_BEGIN nid=ShwpckpQBkA
    [SysAbiExport(
        Nid = "ShwpckpQBkA",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57Product12unsetVersionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0211(CpuContext ctx) => Unset(ctx, 4, 7);
    // V44_EXPORT_END nid=ShwpckpQBkA

    // V44_EXPORT_BEGIN nid=H7-xFNWsKqE
    [SysAbiExport(
        Nid = "H7-xFNWsKqE",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V57Product12versionIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0212(CpuContext ctx) => IsSet(ctx, 4, 7);
    // V44_EXPORT_END nid=H7-xFNWsKqE

    // V44_EXPORT_BEGIN nid=cbHOM72If3c
    [SysAbiExport(
        Nid = "cbHOM72If3c",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57ProductD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0213(CpuContext ctx) => Destruct(ctx, 4);
    // V44_EXPORT_END nid=cbHOM72If3c

    // V44_EXPORT_BEGIN nid=lr0Hd+KZqY0
    [SysAbiExport(
        Nid = "lr0Hd+KZqY0",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V57ProductD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0214(CpuContext ctx) => Destruct(ctx, 4);
    // V44_EXPORT_END nid=lr0Hd+KZqY0

    // V44_EXPORT_BEGIN nid=6-GLBzdKYYM
    [SysAbiExport(
        Nid = "6-GLBzdKYYM",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53SkuC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0235(CpuContext ctx) => Construct(ctx, 5);
    // V44_EXPORT_END nid=6-GLBzdKYYM

    // V44_EXPORT_BEGIN nid=DqHwIDc6J4E
    [SysAbiExport(
        Nid = "DqHwIDc6J4E",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53SkuC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0236(CpuContext ctx) => Construct(ctx, 5);
    // V44_EXPORT_END nid=DqHwIDc6J4E

    // V44_EXPORT_BEGIN nid=w2cA8NF7Vfw
    [SysAbiExport(
        Nid = "w2cA8NF7Vfw",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku14getIsPlusPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0249(CpuContext ctx) => GetValue(ctx, 5, 8, ReturnKind.Bool);
    // V44_EXPORT_END nid=w2cA8NF7Vfw

    // V44_EXPORT_BEGIN nid=U6kDY4BL1L4
    [SysAbiExport(
        Nid = "U6kDY4BL1L4",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku16getOriginalPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0252(CpuContext ctx) => GetValue(ctx, 5, 9, ReturnKind.U32);
    // V44_EXPORT_END nid=U6kDY4BL1L4

    // V44_EXPORT_BEGIN nid=epbO46Swoq8
    [SysAbiExport(
        Nid = "epbO46Swoq8",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku18getPlusUpsellPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0253(CpuContext ctx) => GetValue(ctx, 5, 10, ReturnKind.U32);
    // V44_EXPORT_END nid=epbO46Swoq8

    // V44_EXPORT_BEGIN nid=7QVVkqjdGc0
    [SysAbiExport(
        Nid = "7QVVkqjdGc0",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku8getPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0254(CpuContext ctx) => GetValue(ctx, 5, 11, ReturnKind.U32);
    // V44_EXPORT_END nid=7QVVkqjdGc0

    // V44_EXPORT_BEGIN nid=d0L--Yd9fQc
    [SysAbiExport(
        Nid = "d0L--Yd9fQc",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku11getUseLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0256(CpuContext ctx) => GetValue(ctx, 5, 12, ReturnKind.U32);
    // V44_EXPORT_END nid=d0L--Yd9fQc

    // V44_EXPORT_BEGIN nid=QyVMAhBAwrw
    [SysAbiExport(
        Nid = "QyVMAhBAwrw",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku16isPlusPriceIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0258(CpuContext ctx) => IsSet(ctx, 5, 8);
    // V44_EXPORT_END nid=QyVMAhBAwrw

    // V44_EXPORT_BEGIN nid=HIuzOncLbiw
    [SysAbiExport(
        Nid = "HIuzOncLbiw",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku18originalPriceIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0261(CpuContext ctx) => IsSet(ctx, 5, 9);
    // V44_EXPORT_END nid=HIuzOncLbiw

    // V44_EXPORT_BEGIN nid=xf64ZHPO1ms
    [SysAbiExport(
        Nid = "xf64ZHPO1ms",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku20plusUpsellPriceIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0262(CpuContext ctx) => IsSet(ctx, 5, 10);
    // V44_EXPORT_END nid=xf64ZHPO1ms

    // V44_EXPORT_BEGIN nid=6YlaN3ZykV4
    [SysAbiExport(
        Nid = "6YlaN3ZykV4",
        ExportName = "_ZNK3sce2Np9CppWebApi13InGameCatalog2V53Sku10priceIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0263(CpuContext ctx) => IsSet(ctx, 5, 11);
    // V44_EXPORT_END nid=6YlaN3ZykV4

    // V44_EXPORT_BEGIN nid=7yQMd+x9H-M
    [SysAbiExport(
        Nid = "7yQMd+x9H-M",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku14setIsPlusPriceERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0270(CpuContext ctx) => SetValue(ctx, 5, 8, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=7yQMd+x9H-M

    // V44_EXPORT_BEGIN nid=Wdjktr3c55c
    [SysAbiExport(
        Nid = "Wdjktr3c55c",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku16setOriginalPriceERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0273(CpuContext ctx) => SetValue(ctx, 5, 9, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=Wdjktr3c55c

    // V44_EXPORT_BEGIN nid=DkkJVxRX2g0
    [SysAbiExport(
        Nid = "DkkJVxRX2g0",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku18setPlusUpsellPriceERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0274(CpuContext ctx) => SetValue(ctx, 5, 10, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=DkkJVxRX2g0

    // V44_EXPORT_BEGIN nid=lX2klFcD4z8
    [SysAbiExport(
        Nid = "lX2klFcD4z8",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku8setPriceERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0275(CpuContext ctx) => SetValue(ctx, 5, 11, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=lX2klFcD4z8

    // V44_EXPORT_BEGIN nid=pPikP5n3mmY
    [SysAbiExport(
        Nid = "pPikP5n3mmY",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku11setUseLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0277(CpuContext ctx) => SetValue(ctx, 5, 12, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=pPikP5n3mmY

    // V44_EXPORT_BEGIN nid=30e9+loZaqc
    [SysAbiExport(
        Nid = "30e9+loZaqc",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku16unsetIsPlusPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0286(CpuContext ctx) => Unset(ctx, 5, 8);
    // V44_EXPORT_END nid=30e9+loZaqc

    // V44_EXPORT_BEGIN nid=S5deBYqi9vc
    [SysAbiExport(
        Nid = "S5deBYqi9vc",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku18unsetOriginalPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0289(CpuContext ctx) => Unset(ctx, 5, 9);
    // V44_EXPORT_END nid=S5deBYqi9vc

    // V44_EXPORT_BEGIN nid=tx07rUxYsoU
    [SysAbiExport(
        Nid = "tx07rUxYsoU",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku20unsetPlusUpsellPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0290(CpuContext ctx) => Unset(ctx, 5, 10);
    // V44_EXPORT_END nid=tx07rUxYsoU

    // V44_EXPORT_BEGIN nid=fAGY6E0eqBo
    [SysAbiExport(
        Nid = "fAGY6E0eqBo",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53Sku10unsetPriceEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0291(CpuContext ctx) => Unset(ctx, 5, 11);
    // V44_EXPORT_END nid=fAGY6E0eqBo

    // V44_EXPORT_BEGIN nid=9QqW0QKTIAY
    [SysAbiExport(
        Nid = "9QqW0QKTIAY",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53SkuD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0293(CpuContext ctx) => Destruct(ctx, 5);
    // V44_EXPORT_END nid=9QqW0QKTIAY

    // V44_EXPORT_BEGIN nid=q9YcRtDEijs
    [SysAbiExport(
        Nid = "q9YcRtDEijs",
        ExportName = "_ZN3sce2Np9CppWebApi13InGameCatalog2V53SkuD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0294(CpuContext ctx) => Destruct(ctx, 5);
    // V44_EXPORT_END nid=q9YcRtDEijs

    // V44_EXPORT_BEGIN nid=BKQCiAX1qrk
    [SysAbiExport(
        Nid = "BKQCiAX1qrk",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinition10getboardIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0302(CpuContext ctx) => GetValue(ctx, 6, 13, ReturnKind.U32);
    // V44_EXPORT_END nid=BKQCiAX1qrk

    // V44_EXPORT_BEGIN nid=B2rIJbqSX5k
    [SysAbiExport(
        Nid = "B2rIJbqSX5k",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinition17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0304(CpuContext ctx) => GetValue(ctx, 6, 14, ReturnKind.U32);
    // V44_EXPORT_END nid=B2rIJbqSX5k

    // V44_EXPORT_BEGIN nid=3ocUiA8RVA4
    [SysAbiExport(
        Nid = "3ocUiA8RVA4",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinition17hasnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0306(CpuContext ctx) => IsSet(ctx, 6, 14);
    // V44_EXPORT_END nid=3ocUiA8RVA4

    // V44_EXPORT_BEGIN nid=1YHfWhct218
    [SysAbiExport(
        Nid = "1YHfWhct218",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinition10setboardIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0310(CpuContext ctx) => SetValue(ctx, 6, 13, ValueSource.Register, false);
    // V44_EXPORT_END nid=1YHfWhct218

    // V44_EXPORT_BEGIN nid=TK-C+fGnZik
    [SysAbiExport(
        Nid = "TK-C+fGnZik",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinition17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0312(CpuContext ctx) => SetValue(ctx, 6, 14, ValueSource.Register, false);
    // V44_EXPORT_END nid=TK-C+fGnZik

    // V44_EXPORT_BEGIN nid=DtHnWZafiiA
    [SysAbiExport(
        Nid = "DtHnWZafiiA",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinition19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0315(CpuContext ctx) => Unset(ctx, 6, 14);
    // V44_EXPORT_END nid=DtHnWZafiiA

    // V44_EXPORT_BEGIN nid=iOwunxTavFM
    [SysAbiExport(
        Nid = "iOwunxTavFM",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinitionD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0316(CpuContext ctx) => Destruct(ctx, 6);
    // V44_EXPORT_END nid=iOwunxTavFM

    // V44_EXPORT_BEGIN nid=tJMAm9ZBelo
    [SysAbiExport(
        Nid = "tJMAm9ZBelo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19BoardsApi29ParameterToGetBoardDefinitionD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0317(CpuContext ctx) => Destruct(ctx, 6);
    // V44_EXPORT_END nid=tJMAm9ZBelo

    // V44_EXPORT_BEGIN nid=wxp0--c0U4g
    [SysAbiExport(
        Nid = "wxp0--c0U4g",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15EntryC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0319(CpuContext ctx) => Construct(ctx, 7);
    // V44_EXPORT_END nid=wxp0--c0U4g

    // V44_EXPORT_BEGIN nid=yxrud6sRAWE
    [SysAbiExport(
        Nid = "yxrud6sRAWE",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15EntryC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0320(CpuContext ctx) => Construct(ctx, 7);
    // V44_EXPORT_END nid=yxrud6sRAWE

    // V44_EXPORT_BEGIN nid=Er5RROJCXYo
    [SysAbiExport(
        Nid = "Er5RROJCXYo",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0323(CpuContext ctx) => GetValue(ctx, 7, 15, ReturnKind.U64);
    // V44_EXPORT_END nid=Er5RROJCXYo

    // V44_EXPORT_BEGIN nid=x5fMr5644iE
    [SysAbiExport(
        Nid = "x5fMr5644iE",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry14getHighestRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0325(CpuContext ctx) => GetValue(ctx, 7, 16, ReturnKind.U32);
    // V44_EXPORT_END nid=x5fMr5644iE

    // V44_EXPORT_BEGIN nid=KnCMTTJWLdg
    [SysAbiExport(
        Nid = "KnCMTTJWLdg",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry20getHighestSerialRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0326(CpuContext ctx) => GetValue(ctx, 7, 17, ReturnKind.U32);
    // V44_EXPORT_END nid=KnCMTTJWLdg

    // V44_EXPORT_BEGIN nid=+3KiBw-4CQY
    [SysAbiExport(
        Nid = "+3KiBw-4CQY",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry7getPcIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0329(CpuContext ctx) => GetValue(ctx, 7, 18, ReturnKind.U32);
    // V44_EXPORT_END nid=+3KiBw-4CQY

    // V44_EXPORT_BEGIN nid=zk7Es711EV8
    [SysAbiExport(
        Nid = "zk7Es711EV8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry7getRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0330(CpuContext ctx) => GetValue(ctx, 7, 19, ReturnKind.U32);
    // V44_EXPORT_END nid=zk7Es711EV8

    // V44_EXPORT_BEGIN nid=+631th1Z4DU
    [SysAbiExport(
        Nid = "+631th1Z4DU",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0332(CpuContext ctx) => GetValue(ctx, 7, 20, ReturnKind.U64);
    // V44_EXPORT_END nid=+631th1Z4DU

    // V44_EXPORT_BEGIN nid=PmMi+EcpbpM
    [SysAbiExport(
        Nid = "PmMi+EcpbpM",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry13getSerialRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0333(CpuContext ctx) => GetValue(ctx, 7, 21, ReturnKind.U32);
    // V44_EXPORT_END nid=PmMi+EcpbpM

    // V44_EXPORT_BEGIN nid=OdnfwPg6zUo
    [SysAbiExport(
        Nid = "OdnfwPg6zUo",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Entry9pcIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0336(CpuContext ctx) => IsSet(ctx, 7, 18);
    // V44_EXPORT_END nid=OdnfwPg6zUo

    // V44_EXPORT_BEGIN nid=KyMRVd0swPc
    [SysAbiExport(
        Nid = "KyMRVd0swPc",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0338(CpuContext ctx) => SetValue(ctx, 7, 15, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=KyMRVd0swPc

    // V44_EXPORT_BEGIN nid=CSyTVQgzju4
    [SysAbiExport(
        Nid = "CSyTVQgzju4",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry14setHighestRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0340(CpuContext ctx) => SetValue(ctx, 7, 16, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=CSyTVQgzju4

    // V44_EXPORT_BEGIN nid=oghWcTl49m4
    [SysAbiExport(
        Nid = "oghWcTl49m4",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry20setHighestSerialRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0341(CpuContext ctx) => SetValue(ctx, 7, 17, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=oghWcTl49m4

    // V44_EXPORT_BEGIN nid=tMll44TLd3o
    [SysAbiExport(
        Nid = "tMll44TLd3o",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry7setPcIdERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0344(CpuContext ctx) => SetValue(ctx, 7, 18, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=tMll44TLd3o

    // V44_EXPORT_BEGIN nid=C6Pc5Xu7bxU
    [SysAbiExport(
        Nid = "C6Pc5Xu7bxU",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry7setRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0345(CpuContext ctx) => SetValue(ctx, 7, 19, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=C6Pc5Xu7bxU

    // V44_EXPORT_BEGIN nid=K3oGakljx2w
    [SysAbiExport(
        Nid = "K3oGakljx2w",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry8setScoreERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0347(CpuContext ctx) => SetValue(ctx, 7, 20, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=K3oGakljx2w

    // V44_EXPORT_BEGIN nid=Iv7p0JnxpoQ
    [SysAbiExport(
        Nid = "Iv7p0JnxpoQ",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry13setSerialRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0348(CpuContext ctx) => SetValue(ctx, 7, 21, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=Iv7p0JnxpoQ

    // V44_EXPORT_BEGIN nid=hp37hG7VMKs
    [SysAbiExport(
        Nid = "hp37hG7VMKs",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Entry9unsetPcIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0354(CpuContext ctx) => Unset(ctx, 7, 18);
    // V44_EXPORT_END nid=hp37hG7VMKs

    // V44_EXPORT_BEGIN nid=dmYY7R30gsQ
    [SysAbiExport(
        Nid = "dmYY7R30gsQ",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15EntryD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0357(CpuContext ctx) => Destruct(ctx, 7);
    // V44_EXPORT_END nid=dmYY7R30gsQ

    // V44_EXPORT_BEGIN nid=e1IQ+N9hSKw
    [SysAbiExport(
        Nid = "e1IQ+N9hSKw",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15EntryD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0358(CpuContext ctx) => Destruct(ctx, 7);
    // V44_EXPORT_END nid=e1IQ+N9hSKw

    // V44_EXPORT_BEGIN nid=0wfGuexCjYI
    [SysAbiExport(
        Nid = "0wfGuexCjYI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0362(CpuContext ctx) => Construct(ctx, 8);
    // V44_EXPORT_END nid=0wfGuexCjYI

    // V44_EXPORT_BEGIN nid=taqEUfh8XtI
    [SysAbiExport(
        Nid = "taqEUfh8XtI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0363(CpuContext ctx) => Construct(ctx, 8);
    // V44_EXPORT_END nid=taqEUfh8XtI

    // V44_EXPORT_BEGIN nid=3-MUAUHJg3U
    [SysAbiExport(
        Nid = "3-MUAUHJg3U",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V15Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0365(CpuContext ctx) => GetValue(ctx, 8, 22, ReturnKind.U32);
    // V44_EXPORT_END nid=3-MUAUHJg3U

    // V44_EXPORT_BEGIN nid=jpY0vJLjJ1w
    [SysAbiExport(
        Nid = "jpY0vJLjJ1w",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15Error7setCodeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0369(CpuContext ctx) => SetValue(ctx, 8, 22, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=jpY0vJLjJ1w

    // V44_EXPORT_BEGIN nid=IvMsyTCxaVs
    [SysAbiExport(
        Nid = "IvMsyTCxaVs",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0374(CpuContext ctx) => Destruct(ctx, 8);
    // V44_EXPORT_END nid=IvMsyTCxaVs

    // V44_EXPORT_BEGIN nid=rS3h8f-Dibk
    [SysAbiExport(
        Nid = "rS3h8f-Dibk",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V15ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0375(CpuContext ctx) => Destruct(ctx, 8);
    // V44_EXPORT_END nid=rS3h8f-Dibk

    // V44_EXPORT_BEGIN nid=uTRcZNJiTRs
    [SysAbiExport(
        Nid = "uTRcZNJiTRs",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0390(CpuContext ctx) => Construct(ctx, 9);
    // V44_EXPORT_END nid=uTRcZNJiTRs

    // V44_EXPORT_BEGIN nid=vtVMpp29bkE
    [SysAbiExport(
        Nid = "vtVMpp29bkE",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0391(CpuContext ctx) => Construct(ctx, 9);
    // V44_EXPORT_END nid=vtVMpp29bkE

    // V44_EXPORT_BEGIN nid=lfUiDOAsDoo
    [SysAbiExport(
        Nid = "lfUiDOAsDoo",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody15entryLimitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0392(CpuContext ctx) => IsSet(ctx, 9, 23);
    // V44_EXPORT_END nid=lfUiDOAsDoo

    // V44_EXPORT_BEGIN nid=5avJQwMJgsY
    [SysAbiExport(
        Nid = "5avJQwMJgsY",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody13getEntryLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0394(CpuContext ctx) => GetValue(ctx, 9, 23, ReturnKind.U32);
    // V44_EXPORT_END nid=5avJQwMJgsY

    // V44_EXPORT_BEGIN nid=cq65J5rCEwE
    [SysAbiExport(
        Nid = "cq65J5rCEwE",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody20getLargeDataNumLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0395(CpuContext ctx) => GetValue(ctx, 9, 24, ReturnKind.U32);
    // V44_EXPORT_END nid=cq65J5rCEwE

    // V44_EXPORT_BEGIN nid=KanXmz-cpzE
    [SysAbiExport(
        Nid = "KanXmz-cpzE",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody21getLargeDataSizeLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0396(CpuContext ctx) => GetValue(ctx, 9, 25, ReturnKind.U64);
    // V44_EXPORT_END nid=KanXmz-cpzE

    // V44_EXPORT_BEGIN nid=VhWD7ylSQu8
    [SysAbiExport(
        Nid = "VhWD7ylSQu8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody16getMaxScoreLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0397(CpuContext ctx) => GetValue(ctx, 9, 26, ReturnKind.U64);
    // V44_EXPORT_END nid=VhWD7ylSQu8

    // V44_EXPORT_BEGIN nid=59ZoWcKl5v8
    [SysAbiExport(
        Nid = "59ZoWcKl5v8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody16getMinScoreLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0398(CpuContext ctx) => GetValue(ctx, 9, 27, ReturnKind.U64);
    // V44_EXPORT_END nid=59ZoWcKl5v8

    // V44_EXPORT_BEGIN nid=hQdNOFlDedY
    [SysAbiExport(
        Nid = "hQdNOFlDedY",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody22largeDataNumLimitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0401(CpuContext ctx) => IsSet(ctx, 9, 24);
    // V44_EXPORT_END nid=hQdNOFlDedY

    // V44_EXPORT_BEGIN nid=cJ8md8EbvrI
    [SysAbiExport(
        Nid = "cJ8md8EbvrI",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody23largeDataSizeLimitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0402(CpuContext ctx) => IsSet(ctx, 9, 25);
    // V44_EXPORT_END nid=cJ8md8EbvrI

    // V44_EXPORT_BEGIN nid=DeFsyDHokeY
    [SysAbiExport(
        Nid = "DeFsyDHokeY",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody18maxScoreLimitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0403(CpuContext ctx) => IsSet(ctx, 9, 26);
    // V44_EXPORT_END nid=DeFsyDHokeY

    // V44_EXPORT_BEGIN nid=01ZGV2VvBPU
    [SysAbiExport(
        Nid = "01ZGV2VvBPU",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody18minScoreLimitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0404(CpuContext ctx) => IsSet(ctx, 9, 27);
    // V44_EXPORT_END nid=01ZGV2VvBPU

    // V44_EXPORT_BEGIN nid=BVpUZ+iitmQ
    [SysAbiExport(
        Nid = "BVpUZ+iitmQ",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody13setEntryLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0405(CpuContext ctx) => SetValue(ctx, 9, 23, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=BVpUZ+iitmQ

    // V44_EXPORT_BEGIN nid=FyznWfTyqGI
    [SysAbiExport(
        Nid = "FyznWfTyqGI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody20setLargeDataNumLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0406(CpuContext ctx) => SetValue(ctx, 9, 24, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=FyznWfTyqGI

    // V44_EXPORT_BEGIN nid=PSjy7gaxRfo
    [SysAbiExport(
        Nid = "PSjy7gaxRfo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody21setLargeDataSizeLimitERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0407(CpuContext ctx) => SetValue(ctx, 9, 25, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=PSjy7gaxRfo

    // V44_EXPORT_BEGIN nid=wsDgvrp7L+s
    [SysAbiExport(
        Nid = "wsDgvrp7L+s",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody16setMaxScoreLimitERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0408(CpuContext ctx) => SetValue(ctx, 9, 26, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=wsDgvrp7L+s

    // V44_EXPORT_BEGIN nid=3sVrBLScRtY
    [SysAbiExport(
        Nid = "3sVrBLScRtY",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody16setMinScoreLimitERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0409(CpuContext ctx) => SetValue(ctx, 9, 27, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=3sVrBLScRtY

    // V44_EXPORT_BEGIN nid=D1tyB3jTMDg
    [SysAbiExport(
        Nid = "D1tyB3jTMDg",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody15unsetEntryLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0414(CpuContext ctx) => Unset(ctx, 9, 23);
    // V44_EXPORT_END nid=D1tyB3jTMDg

    // V44_EXPORT_BEGIN nid=6C9EUWfvx7E
    [SysAbiExport(
        Nid = "6C9EUWfvx7E",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody22unsetLargeDataNumLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0415(CpuContext ctx) => Unset(ctx, 9, 24);
    // V44_EXPORT_END nid=6C9EUWfvx7E

    // V44_EXPORT_BEGIN nid=Z3e-bDOHwDY
    [SysAbiExport(
        Nid = "Z3e-bDOHwDY",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody23unsetLargeDataSizeLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0416(CpuContext ctx) => Unset(ctx, 9, 25);
    // V44_EXPORT_END nid=Z3e-bDOHwDY

    // V44_EXPORT_BEGIN nid=Qure-Bsk2fc
    [SysAbiExport(
        Nid = "Qure-Bsk2fc",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody18unsetMaxScoreLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0417(CpuContext ctx) => Unset(ctx, 9, 26);
    // V44_EXPORT_END nid=Qure-Bsk2fc

    // V44_EXPORT_BEGIN nid=C2fPc5Q38TE
    [SysAbiExport(
        Nid = "C2fPc5Q38TE",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBody18unsetMinScoreLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0418(CpuContext ctx) => Unset(ctx, 9, 27);
    // V44_EXPORT_END nid=C2fPc5Q38TE

    // V44_EXPORT_BEGIN nid=C1LBXRglVQA
    [SysAbiExport(
        Nid = "C1LBXRglVQA",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0422(CpuContext ctx) => Destruct(ctx, 9);
    // V44_EXPORT_END nid=C1LBXRglVQA

    // V44_EXPORT_BEGIN nid=RARARMv04ws
    [SysAbiExport(
        Nid = "RARARMv04ws",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V130GetBoardDefinitionResponseBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0423(CpuContext ctx) => Destruct(ctx, 9);
    // V44_EXPORT_END nid=RARARMv04ws

    // V44_EXPORT_BEGIN nid=8J-ZWqhJC+0
    [SysAbiExport(
        Nid = "8J-ZWqhJC+0",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0428(CpuContext ctx) => Construct(ctx, 10);
    // V44_EXPORT_END nid=8J-ZWqhJC+0

    // V44_EXPORT_BEGIN nid=lUHMWrWcowo
    [SysAbiExport(
        Nid = "lUHMWrWcowo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0429(CpuContext ctx) => Construct(ctx, 10);
    // V44_EXPORT_END nid=lUHMWrWcowo

    // V44_EXPORT_BEGIN nid=j+YazVrEz2I
    [SysAbiExport(
        Nid = "j+YazVrEz2I",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody22centerToEdgeLimitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0430(CpuContext ctx) => IsSet(ctx, 10, 28);
    // V44_EXPORT_END nid=j+YazVrEz2I

    // V44_EXPORT_BEGIN nid=nLzU1Fz6FFo
    [SysAbiExport(
        Nid = "nLzU1Fz6FFo",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody20getCenterToEdgeLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0432(CpuContext ctx) => GetValue(ctx, 10, 28, ReturnKind.U32);
    // V44_EXPORT_END nid=nLzU1Fz6FFo

    // V44_EXPORT_BEGIN nid=oJuf3c6iXZA
    [SysAbiExport(
        Nid = "oJuf3c6iXZA",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody8getLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0434(CpuContext ctx) => GetValue(ctx, 10, 29, ReturnKind.U32);
    // V44_EXPORT_END nid=oJuf3c6iXZA

    // V44_EXPORT_BEGIN nid=h8dR9pcJiP8
    [SysAbiExport(
        Nid = "h8dR9pcJiP8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody24getNeedsRecordedDateTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0435(CpuContext ctx) => GetValue(ctx, 10, 30, ReturnKind.Bool);
    // V44_EXPORT_END nid=h8dR9pcJiP8

    // V44_EXPORT_BEGIN nid=YXCKQKvsVqQ
    [SysAbiExport(
        Nid = "YXCKQKvsVqQ",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0436(CpuContext ctx) => GetValue(ctx, 10, 31, ReturnKind.U32);
    // V44_EXPORT_END nid=YXCKQKvsVqQ

    // V44_EXPORT_BEGIN nid=c-dDdbRZbU8
    [SysAbiExport(
        Nid = "c-dDdbRZbU8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody9getOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0437(CpuContext ctx) => GetValue(ctx, 10, 32, ReturnKind.U32);
    // V44_EXPORT_END nid=c-dDdbRZbU8

    // V44_EXPORT_BEGIN nid=PltJvsE1R5U
    [SysAbiExport(
        Nid = "PltJvsE1R5U",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody18getStartSerialRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0438(CpuContext ctx) => GetValue(ctx, 10, 33, ReturnKind.U32);
    // V44_EXPORT_END nid=PltJvsE1R5U

    // V44_EXPORT_BEGIN nid=qyWV8EB3AV4
    [SysAbiExport(
        Nid = "qyWV8EB3AV4",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody10limitIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0442(CpuContext ctx) => IsSet(ctx, 10, 29);
    // V44_EXPORT_END nid=qyWV8EB3AV4

    // V44_EXPORT_BEGIN nid=vZjaJ6+zWIA
    [SysAbiExport(
        Nid = "vZjaJ6+zWIA",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody26needsRecordedDateTimeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0443(CpuContext ctx) => IsSet(ctx, 10, 30);
    // V44_EXPORT_END nid=vZjaJ6+zWIA

    // V44_EXPORT_BEGIN nid=nbmQMuS3p9I
    [SysAbiExport(
        Nid = "nbmQMuS3p9I",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0444(CpuContext ctx) => IsSet(ctx, 10, 31);
    // V44_EXPORT_END nid=nbmQMuS3p9I

    // V44_EXPORT_BEGIN nid=jBLdb1Znt1M
    [SysAbiExport(
        Nid = "jBLdb1Znt1M",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody11offsetIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0445(CpuContext ctx) => IsSet(ctx, 10, 32);
    // V44_EXPORT_END nid=jBLdb1Znt1M

    // V44_EXPORT_BEGIN nid=sFtninKXq8g
    [SysAbiExport(
        Nid = "sFtninKXq8g",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody20setCenterToEdgeLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0446(CpuContext ctx) => SetValue(ctx, 10, 28, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=sFtninKXq8g

    // V44_EXPORT_BEGIN nid=br6GL-f3CQg
    [SysAbiExport(
        Nid = "br6GL-f3CQg",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody8setLimitERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0448(CpuContext ctx) => SetValue(ctx, 10, 29, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=br6GL-f3CQg

    // V44_EXPORT_BEGIN nid=WPSr7BikUnE
    [SysAbiExport(
        Nid = "WPSr7BikUnE",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody24setNeedsRecordedDateTimeERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0449(CpuContext ctx) => SetValue(ctx, 10, 30, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=WPSr7BikUnE

    // V44_EXPORT_BEGIN nid=vx4I6uMoiww
    [SysAbiExport(
        Nid = "vx4I6uMoiww",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody17setNpServiceLabelERKj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0450(CpuContext ctx) => SetValue(ctx, 10, 31, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=vx4I6uMoiww

    // V44_EXPORT_BEGIN nid=khThzVltokg
    [SysAbiExport(
        Nid = "khThzVltokg",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody9setOffsetERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0451(CpuContext ctx) => SetValue(ctx, 10, 32, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=khThzVltokg

    // V44_EXPORT_BEGIN nid=YKVixVJQoXU
    [SysAbiExport(
        Nid = "YKVixVJQoXU",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody18setStartSerialRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0452(CpuContext ctx) => SetValue(ctx, 10, 33, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=YKVixVJQoXU

    // V44_EXPORT_BEGIN nid=mddy1zct34Q
    [SysAbiExport(
        Nid = "mddy1zct34Q",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody20startSerialRankIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0455(CpuContext ctx) => IsSet(ctx, 10, 33);
    // V44_EXPORT_END nid=mddy1zct34Q

    // V44_EXPORT_BEGIN nid=BOLp9C1MCgk
    [SysAbiExport(
        Nid = "BOLp9C1MCgk",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody22unsetCenterToEdgeLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0457(CpuContext ctx) => Unset(ctx, 10, 28);
    // V44_EXPORT_END nid=BOLp9C1MCgk

    // V44_EXPORT_BEGIN nid=FFbs7VK+504
    [SysAbiExport(
        Nid = "FFbs7VK+504",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody10unsetLimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0459(CpuContext ctx) => Unset(ctx, 10, 29);
    // V44_EXPORT_END nid=FFbs7VK+504

    // V44_EXPORT_BEGIN nid=-aQEcE0Vcao
    [SysAbiExport(
        Nid = "-aQEcE0Vcao",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody26unsetNeedsRecordedDateTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0460(CpuContext ctx) => Unset(ctx, 10, 30);
    // V44_EXPORT_END nid=-aQEcE0Vcao

    // V44_EXPORT_BEGIN nid=Wfzh10yFbVM
    [SysAbiExport(
        Nid = "Wfzh10yFbVM",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0461(CpuContext ctx) => Unset(ctx, 10, 31);
    // V44_EXPORT_END nid=Wfzh10yFbVM

    // V44_EXPORT_BEGIN nid=l6RswpAwdFw
    [SysAbiExport(
        Nid = "l6RswpAwdFw",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody11unsetOffsetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0462(CpuContext ctx) => Unset(ctx, 10, 32);
    // V44_EXPORT_END nid=l6RswpAwdFw

    // V44_EXPORT_BEGIN nid=yOUEV9uQzCs
    [SysAbiExport(
        Nid = "yOUEV9uQzCs",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBody20unsetStartSerialRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0463(CpuContext ctx) => Unset(ctx, 10, 33);
    // V44_EXPORT_END nid=yOUEV9uQzCs

    // V44_EXPORT_BEGIN nid=FyPe4Yj0RRg
    [SysAbiExport(
        Nid = "FyPe4Yj0RRg",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0468(CpuContext ctx) => Destruct(ctx, 10);
    // V44_EXPORT_END nid=FyPe4Yj0RRg

    // V44_EXPORT_BEGIN nid=hl9hJMTjmQM
    [SysAbiExport(
        Nid = "hl9hJMTjmQM",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V121GetRankingRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0469(CpuContext ctx) => Destruct(ctx, 10);
    // V44_EXPORT_END nid=hl9hJMTjmQM

    // V44_EXPORT_BEGIN nid=2VF3mEweOpI
    [SysAbiExport(
        Nid = "2VF3mEweOpI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122GetRankingResponseBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0473(CpuContext ctx) => Construct(ctx, 11);
    // V44_EXPORT_END nid=2VF3mEweOpI

    // V44_EXPORT_BEGIN nid=mqHr2lV6TJA
    [SysAbiExport(
        Nid = "mqHr2lV6TJA",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122GetRankingResponseBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0474(CpuContext ctx) => Construct(ctx, 11);
    // V44_EXPORT_END nid=mqHr2lV6TJA

    // V44_EXPORT_BEGIN nid=iRNZ5GV5b0Q
    [SysAbiExport(
        Nid = "iRNZ5GV5b0Q",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122GetRankingResponseBody18getTotalEntryCountEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0479(CpuContext ctx) => GetValue(ctx, 11, 34, ReturnKind.U32);
    // V44_EXPORT_END nid=iRNZ5GV5b0Q

    // V44_EXPORT_BEGIN nid=HuvWHTju1hA
    [SysAbiExport(
        Nid = "HuvWHTju1hA",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122GetRankingResponseBody18setTotalEntryCountERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0482(CpuContext ctx) => SetValue(ctx, 11, 34, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=HuvWHTju1hA

    // V44_EXPORT_BEGIN nid=rVkZUDFdolc
    [SysAbiExport(
        Nid = "rVkZUDFdolc",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122GetRankingResponseBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0485(CpuContext ctx) => Destruct(ctx, 11);
    // V44_EXPORT_END nid=rVkZUDFdolc

    // V44_EXPORT_BEGIN nid=w6dfLpf9Os4
    [SysAbiExport(
        Nid = "w6dfLpf9Os4",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122GetRankingResponseBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0486(CpuContext ctx) => Destruct(ctx, 11);
    // V44_EXPORT_END nid=w6dfLpf9Os4

    // V44_EXPORT_BEGIN nid=K1HFWu7lqOQ
    [SysAbiExport(
        Nid = "K1HFWu7lqOQ",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeData10getboardIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0495(CpuContext ctx) => GetValue(ctx, 12, 35, ReturnKind.U32);
    // V44_EXPORT_END nid=K1HFWu7lqOQ

    // V44_EXPORT_BEGIN nid=kWomUmHDEbE
    [SysAbiExport(
        Nid = "kWomUmHDEbE",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeData21getxPsnNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0498(CpuContext ctx) => GetValue(ctx, 12, 36, ReturnKind.U32);
    // V44_EXPORT_END nid=kWomUmHDEbE

    // V44_EXPORT_BEGIN nid=9Rq7mQXOSL4
    [SysAbiExport(
        Nid = "9Rq7mQXOSL4",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeData21hasxPsnNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0499(CpuContext ctx) => IsSet(ctx, 12, 36);
    // V44_EXPORT_END nid=9Rq7mQXOSL4

    // V44_EXPORT_BEGIN nid=6whcJMHioXw
    [SysAbiExport(
        Nid = "6whcJMHioXw",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeData10setboardIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0503(CpuContext ctx) => SetValue(ctx, 12, 35, ValueSource.Register, false);
    // V44_EXPORT_END nid=6whcJMHioXw

    // V44_EXPORT_BEGIN nid=ZomYHcRMgOo
    [SysAbiExport(
        Nid = "ZomYHcRMgOo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeData21setxPsnNpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0506(CpuContext ctx) => SetValue(ctx, 12, 36, ValueSource.Register, false);
    // V44_EXPORT_END nid=ZomYHcRMgOo

    // V44_EXPORT_BEGIN nid=Q99wm1uFrds
    [SysAbiExport(
        Nid = "Q99wm1uFrds",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeData23unsetxPsnNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0508(CpuContext ctx) => Unset(ctx, 12, 36);
    // V44_EXPORT_END nid=Q99wm1uFrds

    // V44_EXPORT_BEGIN nid=LRjPCtnBg4c
    [SysAbiExport(
        Nid = "LRjPCtnBg4c",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeDataD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0509(CpuContext ctx) => Destruct(ctx, 12);
    // V44_EXPORT_END nid=LRjPCtnBg4c

    // V44_EXPORT_BEGIN nid=LwGrNk25QbE
    [SysAbiExport(
        Nid = "LwGrNk25QbE",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi26ParameterToRecordLargeDataD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0510(CpuContext ctx) => Destruct(ctx, 12);
    // V44_EXPORT_END nid=LwGrNk25QbE

    // V44_EXPORT_BEGIN nid=B6TkLyTY1vc
    [SysAbiExport(
        Nid = "B6TkLyTY1vc",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V19RecordApi22ParameterToRecordScore10getboardIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0515(CpuContext ctx) => GetValue(ctx, 13, 37, ReturnKind.U32);
    // V44_EXPORT_END nid=B6TkLyTY1vc

    // V44_EXPORT_BEGIN nid=lFOylbeWySU
    [SysAbiExport(
        Nid = "lFOylbeWySU",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi22ParameterToRecordScore10setboardIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0522(CpuContext ctx) => SetValue(ctx, 13, 37, ValueSource.Register, false);
    // V44_EXPORT_END nid=lFOylbeWySU

    // V44_EXPORT_BEGIN nid=3WzgZDZnfdo
    [SysAbiExport(
        Nid = "3WzgZDZnfdo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi22ParameterToRecordScoreD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0527(CpuContext ctx) => Destruct(ctx, 13);
    // V44_EXPORT_END nid=3WzgZDZnfdo

    // V44_EXPORT_BEGIN nid=4TGeM5jD7x0
    [SysAbiExport(
        Nid = "4TGeM5jD7x0",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V19RecordApi22ParameterToRecordScoreD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0528(CpuContext ctx) => Destruct(ctx, 13);
    // V44_EXPORT_END nid=4TGeM5jD7x0

    // V44_EXPORT_BEGIN nid=-ptjV9t-QiA
    [SysAbiExport(
        Nid = "-ptjV9t-QiA",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0567(CpuContext ctx) => Construct(ctx, 14);
    // V44_EXPORT_END nid=-ptjV9t-QiA

    // V44_EXPORT_BEGIN nid=yy4ipwYOGJU
    [SysAbiExport(
        Nid = "yy4ipwYOGJU",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0568(CpuContext ctx) => Construct(ctx, 14);
    // V44_EXPORT_END nid=yy4ipwYOGJU

    // V44_EXPORT_BEGIN nid=SOCxwiW2uqw
    [SysAbiExport(
        Nid = "SOCxwiW2uqw",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody15getNeedsTmpRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0574(CpuContext ctx) => GetValue(ctx, 14, 38, ReturnKind.Bool);
    // V44_EXPORT_END nid=SOCxwiW2uqw

    // V44_EXPORT_BEGIN nid=M-7DI8ISBpo
    [SysAbiExport(
        Nid = "M-7DI8ISBpo",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0575(CpuContext ctx) => GetValue(ctx, 14, 39, ReturnKind.U32);
    // V44_EXPORT_END nid=M-7DI8ISBpo

    // V44_EXPORT_BEGIN nid=GrZjCgU8MOI
    [SysAbiExport(
        Nid = "GrZjCgU8MOI",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody7getPcIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0576(CpuContext ctx) => GetValue(ctx, 14, 40, ReturnKind.U32);
    // V44_EXPORT_END nid=GrZjCgU8MOI

    // V44_EXPORT_BEGIN nid=YTXbepPCE0g
    [SysAbiExport(
        Nid = "YTXbepPCE0g",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0577(CpuContext ctx) => GetValue(ctx, 14, 41, ReturnKind.U64);
    // V44_EXPORT_END nid=YTXbepPCE0g

    // V44_EXPORT_BEGIN nid=Kfz+Xg4hJiA
    [SysAbiExport(
        Nid = "Kfz+Xg4hJiA",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody15getWaitsForDataEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0579(CpuContext ctx) => GetValue(ctx, 14, 42, ReturnKind.Bool);
    // V44_EXPORT_END nid=Kfz+Xg4hJiA

    // V44_EXPORT_BEGIN nid=cnXE+5t5qIc
    [SysAbiExport(
        Nid = "cnXE+5t5qIc",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody17needsTmpRankIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0580(CpuContext ctx) => IsSet(ctx, 14, 38);
    // V44_EXPORT_END nid=cnXE+5t5qIc

    // V44_EXPORT_BEGIN nid=3r35V2b+MH0
    [SysAbiExport(
        Nid = "3r35V2b+MH0",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0581(CpuContext ctx) => IsSet(ctx, 14, 39);
    // V44_EXPORT_END nid=3r35V2b+MH0

    // V44_EXPORT_BEGIN nid=ZN4Udtplcb8
    [SysAbiExport(
        Nid = "ZN4Udtplcb8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody9pcIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0582(CpuContext ctx) => IsSet(ctx, 14, 40);
    // V44_EXPORT_END nid=ZN4Udtplcb8

    // V44_EXPORT_BEGIN nid=4tEx7tt+b7g
    [SysAbiExport(
        Nid = "4tEx7tt+b7g",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody15setNeedsTmpRankERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0585(CpuContext ctx) => SetValue(ctx, 14, 38, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=4tEx7tt+b7g

    // V44_EXPORT_BEGIN nid=m5DU6GnjSlo
    [SysAbiExport(
        Nid = "m5DU6GnjSlo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody17setNpServiceLabelERKj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0586(CpuContext ctx) => SetValue(ctx, 14, 39, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=m5DU6GnjSlo

    // V44_EXPORT_BEGIN nid=jfCufYd0-+s
    [SysAbiExport(
        Nid = "jfCufYd0-+s",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody7setPcIdERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0587(CpuContext ctx) => SetValue(ctx, 14, 40, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=jfCufYd0-+s

    // V44_EXPORT_BEGIN nid=hrctaZQop40
    [SysAbiExport(
        Nid = "hrctaZQop40",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody8setScoreERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0588(CpuContext ctx) => SetValue(ctx, 14, 41, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=hrctaZQop40

    // V44_EXPORT_BEGIN nid=33WTIzHLTe4
    [SysAbiExport(
        Nid = "33WTIzHLTe4",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody15setWaitsForDataERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0590(CpuContext ctx) => SetValue(ctx, 14, 42, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=33WTIzHLTe4

    // V44_EXPORT_BEGIN nid=m5KvMLs-5fE
    [SysAbiExport(
        Nid = "m5KvMLs-5fE",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody17unsetNeedsTmpRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0595(CpuContext ctx) => Unset(ctx, 14, 38);
    // V44_EXPORT_END nid=m5KvMLs-5fE

    // V44_EXPORT_BEGIN nid=6hd30WWn0Fo
    [SysAbiExport(
        Nid = "6hd30WWn0Fo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0596(CpuContext ctx) => Unset(ctx, 14, 39);
    // V44_EXPORT_END nid=6hd30WWn0Fo

    // V44_EXPORT_BEGIN nid=96kVLpVimmw
    [SysAbiExport(
        Nid = "96kVLpVimmw",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody9unsetPcIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0597(CpuContext ctx) => Unset(ctx, 14, 40);
    // V44_EXPORT_END nid=96kVLpVimmw

    // V44_EXPORT_BEGIN nid=CL4mkkTpqLA
    [SysAbiExport(
        Nid = "CL4mkkTpqLA",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody17unsetWaitsForDataEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0599(CpuContext ctx) => Unset(ctx, 14, 42);
    // V44_EXPORT_END nid=CL4mkkTpqLA

    // V44_EXPORT_BEGIN nid=rErIKbleNdk
    [SysAbiExport(
        Nid = "rErIKbleNdk",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBody17waitsForDataIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0600(CpuContext ctx) => IsSet(ctx, 14, 42);
    // V44_EXPORT_END nid=rErIKbleNdk

    // V44_EXPORT_BEGIN nid=MV8JpKlSOlI
    [SysAbiExport(
        Nid = "MV8JpKlSOlI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0601(CpuContext ctx) => Destruct(ctx, 14);
    // V44_EXPORT_END nid=MV8JpKlSOlI

    // V44_EXPORT_BEGIN nid=PR9JxM5XUHw
    [SysAbiExport(
        Nid = "PR9JxM5XUHw",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V122RecordScoreRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0602(CpuContext ctx) => Destruct(ctx, 14);
    // V44_EXPORT_END nid=PR9JxM5XUHw

    // V44_EXPORT_BEGIN nid=50W6WJgJaQ8
    [SysAbiExport(
        Nid = "50W6WJgJaQ8",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0606(CpuContext ctx) => Construct(ctx, 15);
    // V44_EXPORT_END nid=50W6WJgJaQ8

    // V44_EXPORT_BEGIN nid=CSXnwqXBe4A
    [SysAbiExport(
        Nid = "CSXnwqXBe4A",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0607(CpuContext ctx) => Construct(ctx, 15);
    // V44_EXPORT_END nid=CSXnwqXBe4A

    // V44_EXPORT_BEGIN nid=dcbbhKIZCDA
    [SysAbiExport(
        Nid = "dcbbhKIZCDA",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBody10getTmpRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0609(CpuContext ctx) => GetValue(ctx, 15, 43, ReturnKind.U32);
    // V44_EXPORT_END nid=dcbbhKIZCDA

    // V44_EXPORT_BEGIN nid=39c+H8bSITU
    [SysAbiExport(
        Nid = "39c+H8bSITU",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBody16getTmpSerialRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0610(CpuContext ctx) => GetValue(ctx, 15, 44, ReturnKind.U32);
    // V44_EXPORT_END nid=39c+H8bSITU

    // V44_EXPORT_BEGIN nid=1GuRWk-FBlI
    [SysAbiExport(
        Nid = "1GuRWk-FBlI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBody10setTmpRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0611(CpuContext ctx) => SetValue(ctx, 15, 43, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=1GuRWk-FBlI

    // V44_EXPORT_BEGIN nid=B7elLSJ8Wkk
    [SysAbiExport(
        Nid = "B7elLSJ8Wkk",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBody16setTmpSerialRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0612(CpuContext ctx) => SetValue(ctx, 15, 44, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=B7elLSJ8Wkk

    // V44_EXPORT_BEGIN nid=RZG1q+gKmjY
    [SysAbiExport(
        Nid = "RZG1q+gKmjY",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0614(CpuContext ctx) => Destruct(ctx, 15);
    // V44_EXPORT_END nid=RZG1q+gKmjY

    // V44_EXPORT_BEGIN nid=niZ0v7ZxaQ8
    [SysAbiExport(
        Nid = "niZ0v7ZxaQ8",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V123RecordScoreResponseBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0615(CpuContext ctx) => Destruct(ctx, 15);
    // V44_EXPORT_END nid=niZ0v7ZxaQ8

    // V44_EXPORT_BEGIN nid=AYdagz+jPcI
    [SysAbiExport(
        Nid = "AYdagz+jPcI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14UserC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0620(CpuContext ctx) => Construct(ctx, 16);
    // V44_EXPORT_END nid=AYdagz+jPcI

    // V44_EXPORT_BEGIN nid=luULJAkiLXg
    [SysAbiExport(
        Nid = "luULJAkiLXg",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14UserC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0621(CpuContext ctx) => Construct(ctx, 16);
    // V44_EXPORT_END nid=luULJAkiLXg

    // V44_EXPORT_BEGIN nid=YMAmjPlj8u8
    [SysAbiExport(
        Nid = "YMAmjPlj8u8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V14User14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0622(CpuContext ctx) => IsSet(ctx, 16, 45);
    // V44_EXPORT_END nid=YMAmjPlj8u8

    // V44_EXPORT_BEGIN nid=iD+dQKaJuU8
    [SysAbiExport(
        Nid = "iD+dQKaJuU8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V14User12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0624(CpuContext ctx) => GetValue(ctx, 16, 45, ReturnKind.U64);
    // V44_EXPORT_END nid=iD+dQKaJuU8

    // V44_EXPORT_BEGIN nid=g4OMF45UKY8
    [SysAbiExport(
        Nid = "g4OMF45UKY8",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V14User7getPcIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0625(CpuContext ctx) => GetValue(ctx, 16, 46, ReturnKind.U32);
    // V44_EXPORT_END nid=g4OMF45UKY8

    // V44_EXPORT_BEGIN nid=Y-f8NxVe1Ws
    [SysAbiExport(
        Nid = "Y-f8NxVe1Ws",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V14User9pcIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0626(CpuContext ctx) => IsSet(ctx, 16, 46);
    // V44_EXPORT_END nid=Y-f8NxVe1Ws

    // V44_EXPORT_BEGIN nid=wJWqKZOj4Ts
    [SysAbiExport(
        Nid = "wJWqKZOj4Ts",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14User12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0627(CpuContext ctx) => SetValue(ctx, 16, 45, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=wJWqKZOj4Ts

    // V44_EXPORT_BEGIN nid=KXllpv1tR48
    [SysAbiExport(
        Nid = "KXllpv1tR48",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14User7setPcIdERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0628(CpuContext ctx) => SetValue(ctx, 16, 46, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=KXllpv1tR48

    // V44_EXPORT_BEGIN nid=qCy8xtv0opg
    [SysAbiExport(
        Nid = "qCy8xtv0opg",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14User14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0630(CpuContext ctx) => Unset(ctx, 16, 45);
    // V44_EXPORT_END nid=qCy8xtv0opg

    // V44_EXPORT_BEGIN nid=EwIYjHJpkKU
    [SysAbiExport(
        Nid = "EwIYjHJpkKU",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14User9unsetPcIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0631(CpuContext ctx) => Unset(ctx, 16, 46);
    // V44_EXPORT_END nid=EwIYjHJpkKU

    // V44_EXPORT_BEGIN nid=oLTNauw+zcc
    [SysAbiExport(
        Nid = "oLTNauw+zcc",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14UserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0632(CpuContext ctx) => Destruct(ctx, 16);
    // V44_EXPORT_END nid=oLTNauw+zcc

    // V44_EXPORT_BEGIN nid=tsUeTvSZGnc
    [SysAbiExport(
        Nid = "tsUeTvSZGnc",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V14UserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0633(CpuContext ctx) => Destruct(ctx, 16);
    // V44_EXPORT_END nid=tsUeTvSZGnc

    // V44_EXPORT_BEGIN nid=ejyZg6hEE3U
    [SysAbiExport(
        Nid = "ejyZg6hEE3U",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V17ViewApi33ParameterToGetLargeDataByObjectId17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0661(CpuContext ctx) => GetValue(ctx, 17, 47, ReturnKind.U32);
    // V44_EXPORT_END nid=ejyZg6hEE3U

    // V44_EXPORT_BEGIN nid=4VPIDrOGoq4
    [SysAbiExport(
        Nid = "4VPIDrOGoq4",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V17ViewApi33ParameterToGetLargeDataByObjectId17hasnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0665(CpuContext ctx) => IsSet(ctx, 17, 47);
    // V44_EXPORT_END nid=4VPIDrOGoq4

    // V44_EXPORT_BEGIN nid=XLDdP3+ELyM
    [SysAbiExport(
        Nid = "XLDdP3+ELyM",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V17ViewApi33ParameterToGetLargeDataByObjectId17setnpServiceLabelEj",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0671(CpuContext ctx) => SetValue(ctx, 17, 47, ValueSource.Register, false);
    // V44_EXPORT_END nid=XLDdP3+ELyM

    // V44_EXPORT_BEGIN nid=rW6vq2T7+yo
    [SysAbiExport(
        Nid = "rW6vq2T7+yo",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V17ViewApi33ParameterToGetLargeDataByObjectId19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0676(CpuContext ctx) => Unset(ctx, 17, 47);
    // V44_EXPORT_END nid=rW6vq2T7+yo

    // V44_EXPORT_BEGIN nid=N0V2-p-0hAM
    [SysAbiExport(
        Nid = "N0V2-p-0hAM",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V17ViewApi33ParameterToGetLargeDataByObjectIdD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0678(CpuContext ctx) => Destruct(ctx, 17);
    // V44_EXPORT_END nid=N0V2-p-0hAM

    // V44_EXPORT_BEGIN nid=nN-ZPSBQrCI
    [SysAbiExport(
        Nid = "nN-ZPSBQrCI",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V17ViewApi33ParameterToGetLargeDataByObjectIdD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0679(CpuContext ctx) => Destruct(ctx, 17);
    // V44_EXPORT_END nid=nN-ZPSBQrCI

    // V44_EXPORT_BEGIN nid=hx-gaKoc9jw
    [SysAbiExport(
        Nid = "hx-gaKoc9jw",
        ExportName = "_ZNK3sce2Np9CppWebApi12Leaderboards2V17ViewApi21ParameterToGetRanking10getboardIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0684(CpuContext ctx) => GetValue(ctx, 18, 48, ReturnKind.U32);
    // V44_EXPORT_END nid=hx-gaKoc9jw

    // V44_EXPORT_BEGIN nid=4zYmu-s0cLU
    [SysAbiExport(
        Nid = "4zYmu-s0cLU",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V17ViewApi21ParameterToGetRanking10setboardIdEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0690(CpuContext ctx) => SetValue(ctx, 18, 48, ValueSource.Register, false);
    // V44_EXPORT_END nid=4zYmu-s0cLU

    // V44_EXPORT_BEGIN nid=9Tb09M8E6yE
    [SysAbiExport(
        Nid = "9Tb09M8E6yE",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V17ViewApi21ParameterToGetRankingD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0694(CpuContext ctx) => Destruct(ctx, 18);
    // V44_EXPORT_END nid=9Tb09M8E6yE

    // V44_EXPORT_BEGIN nid=XtFyTKi22Sc
    [SysAbiExport(
        Nid = "XtFyTKi22Sc",
        ExportName = "_ZN3sce2Np9CppWebApi12Leaderboards2V17ViewApi21ParameterToGetRankingD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0695(CpuContext ctx) => Destruct(ctx, 18);
    // V44_EXPORT_END nid=XtFyTKi22Sc

    // V44_EXPORT_BEGIN nid=GNM0CPnOTjM
    [SysAbiExport(
        Nid = "GNM0CPnOTjM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequestC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0756(CpuContext ctx) => Construct(ctx, 19);
    // V44_EXPORT_END nid=GNM0CPnOTjM

    // V44_EXPORT_BEGIN nid=xwAg3lsPCus
    [SysAbiExport(
        Nid = "xwAg3lsPCus",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequestC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0757(CpuContext ctx) => Construct(ctx, 19);
    // V44_EXPORT_END nid=xwAg3lsPCus

    // V44_EXPORT_BEGIN nid=U883DGbsPFg
    [SysAbiExport(
        Nid = "U883DGbsPFg",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118CreateMatchRequest21cancellationTimeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0758(CpuContext ctx) => IsSet(ctx, 19, 49);
    // V44_EXPORT_END nid=U883DGbsPFg

    // V44_EXPORT_BEGIN nid=zY3+DACnnfE
    [SysAbiExport(
        Nid = "zY3+DACnnfE",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118CreateMatchRequest19expirationTimeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0760(CpuContext ctx) => IsSet(ctx, 19, 50);
    // V44_EXPORT_END nid=zY3+DACnnfE

    // V44_EXPORT_BEGIN nid=7rjDj4OaSZI
    [SysAbiExport(
        Nid = "7rjDj4OaSZI",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118CreateMatchRequest19getCancellationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0763(CpuContext ctx) => GetValue(ctx, 19, 49, ReturnKind.U32);
    // V44_EXPORT_END nid=7rjDj4OaSZI

    // V44_EXPORT_BEGIN nid=xC8OivuT6nQ
    [SysAbiExport(
        Nid = "xC8OivuT6nQ",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118CreateMatchRequest17getExpirationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0765(CpuContext ctx) => GetValue(ctx, 19, 50, ReturnKind.U32);
    // V44_EXPORT_END nid=xC8OivuT6nQ

    // V44_EXPORT_BEGIN nid=GuWdK+yg4ho
    [SysAbiExport(
        Nid = "GuWdK+yg4ho",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118CreateMatchRequest17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0767(CpuContext ctx) => GetValue(ctx, 19, 51, ReturnKind.U32);
    // V44_EXPORT_END nid=GuWdK+yg4ho

    // V44_EXPORT_BEGIN nid=jng0x3KHPkg
    [SysAbiExport(
        Nid = "jng0x3KHPkg",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118CreateMatchRequest19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0770(CpuContext ctx) => IsSet(ctx, 19, 51);
    // V44_EXPORT_END nid=jng0x3KHPkg

    // V44_EXPORT_BEGIN nid=Sv6Ikb2tojM
    [SysAbiExport(
        Nid = "Sv6Ikb2tojM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequest19setCancellationTimeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0772(CpuContext ctx) => SetValue(ctx, 19, 49, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=Sv6Ikb2tojM

    // V44_EXPORT_BEGIN nid=eSiHCxqbKas
    [SysAbiExport(
        Nid = "eSiHCxqbKas",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequest17setExpirationTimeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0774(CpuContext ctx) => SetValue(ctx, 19, 50, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=eSiHCxqbKas

    // V44_EXPORT_BEGIN nid=+e3Bdk+MqN8
    [SysAbiExport(
        Nid = "+e3Bdk+MqN8",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequest17setNpServiceLabelERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0776(CpuContext ctx) => SetValue(ctx, 19, 51, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=+e3Bdk+MqN8

    // V44_EXPORT_BEGIN nid=Auc6i3VTZ4c
    [SysAbiExport(
        Nid = "Auc6i3VTZ4c",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequest21unsetCancellationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0779(CpuContext ctx) => Unset(ctx, 19, 49);
    // V44_EXPORT_END nid=Auc6i3VTZ4c

    // V44_EXPORT_BEGIN nid=aVdYj+lcSXw
    [SysAbiExport(
        Nid = "aVdYj+lcSXw",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequest19unsetExpirationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0781(CpuContext ctx) => Unset(ctx, 19, 50);
    // V44_EXPORT_END nid=aVdYj+lcSXw

    // V44_EXPORT_BEGIN nid=9Dm5f-FuT8c
    [SysAbiExport(
        Nid = "9Dm5f-FuT8c",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequest19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0783(CpuContext ctx) => Unset(ctx, 19, 51);
    // V44_EXPORT_END nid=9Dm5f-FuT8c

    // V44_EXPORT_BEGIN nid=AmFhOPPRYW4
    [SysAbiExport(
        Nid = "AmFhOPPRYW4",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequestD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0786(CpuContext ctx) => Destruct(ctx, 19);
    // V44_EXPORT_END nid=AmFhOPPRYW4

    // V44_EXPORT_BEGIN nid=nslHuWRPL80
    [SysAbiExport(
        Nid = "nslHuWRPL80",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118CreateMatchRequestD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0787(CpuContext ctx) => Destruct(ctx, 19);
    // V44_EXPORT_END nid=nslHuWRPL80

    // V44_EXPORT_BEGIN nid=6JFErPfBZ+U
    [SysAbiExport(
        Nid = "6JFErPfBZ+U",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V15ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0803(CpuContext ctx) => Construct(ctx, 20);
    // V44_EXPORT_END nid=6JFErPfBZ+U

    // V44_EXPORT_BEGIN nid=HQMDEdrkt1E
    [SysAbiExport(
        Nid = "HQMDEdrkt1E",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V15ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0804(CpuContext ctx) => Construct(ctx, 20);
    // V44_EXPORT_END nid=HQMDEdrkt1E

    // V44_EXPORT_BEGIN nid=AfX8I7C66fE
    [SysAbiExport(
        Nid = "AfX8I7C66fE",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V15Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0806(CpuContext ctx) => GetValue(ctx, 20, 52, ReturnKind.U32);
    // V44_EXPORT_END nid=AfX8I7C66fE

    // V44_EXPORT_BEGIN nid=Zylp1RmlarU
    [SysAbiExport(
        Nid = "Zylp1RmlarU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V15Error7setCodeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0813(CpuContext ctx) => SetValue(ctx, 20, 52, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=Zylp1RmlarU

    // V44_EXPORT_BEGIN nid=hTsSi8mmeBE
    [SysAbiExport(
        Nid = "hTsSi8mmeBE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V15ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0823(CpuContext ctx) => Destruct(ctx, 20);
    // V44_EXPORT_END nid=hTsSi8mmeBE

    // V44_EXPORT_BEGIN nid=oggz4E+E8Mc
    [SysAbiExport(
        Nid = "oggz4E+E8Mc",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V15ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0824(CpuContext ctx) => Destruct(ctx, 20);
    // V44_EXPORT_END nid=oggz4E+E8Mc

    // V44_EXPORT_BEGIN nid=Lt7u5PXrxpc
    [SysAbiExport(
        Nid = "Lt7u5PXrxpc",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0839(CpuContext ctx) => Construct(ctx, 21);
    // V44_EXPORT_END nid=Lt7u5PXrxpc

    // V44_EXPORT_BEGIN nid=jn95S8jrpJA
    [SysAbiExport(
        Nid = "jn95S8jrpJA",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0840(CpuContext ctx) => Construct(ctx, 21);
    // V44_EXPORT_END nid=jn95S8jrpJA

    // V44_EXPORT_BEGIN nid=Y2MJ-3r8EUg
    [SysAbiExport(
        Nid = "Y2MJ-3r8EUg",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponse21cancellationTimeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0841(CpuContext ctx) => IsSet(ctx, 21, 53);
    // V44_EXPORT_END nid=Y2MJ-3r8EUg

    // V44_EXPORT_BEGIN nid=buTAjf8FCb4
    [SysAbiExport(
        Nid = "buTAjf8FCb4",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponse19getCancellationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0845(CpuContext ctx) => GetValue(ctx, 21, 53, ReturnKind.U32);
    // V44_EXPORT_END nid=buTAjf8FCb4

    // V44_EXPORT_BEGIN nid=dY6vQe8+YfA
    [SysAbiExport(
        Nid = "dY6vQe8+YfA",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponse17getExpirationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0848(CpuContext ctx) => GetValue(ctx, 21, 54, ReturnKind.U32);
    // V44_EXPORT_END nid=dY6vQe8+YfA

    // V44_EXPORT_BEGIN nid=tEjFmn-2SRE
    [SysAbiExport(
        Nid = "tEjFmn-2SRE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponse19setCancellationTimeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0870(CpuContext ctx) => SetValue(ctx, 21, 53, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=tEjFmn-2SRE

    // V44_EXPORT_BEGIN nid=2gLmRbOOBKE
    [SysAbiExport(
        Nid = "2gLmRbOOBKE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponse17setExpirationTimeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0873(CpuContext ctx) => SetValue(ctx, 21, 54, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=2gLmRbOOBKE

    // V44_EXPORT_BEGIN nid=W9oHsE8wkhE
    [SysAbiExport(
        Nid = "W9oHsE8wkhE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponse21unsetCancellationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0889(CpuContext ctx) => Unset(ctx, 21, 53);
    // V44_EXPORT_END nid=W9oHsE8wkhE

    // V44_EXPORT_BEGIN nid=em1os75YZXQ
    [SysAbiExport(
        Nid = "em1os75YZXQ",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0901(CpuContext ctx) => Destruct(ctx, 21);
    // V44_EXPORT_END nid=em1os75YZXQ

    // V44_EXPORT_BEGIN nid=f0jfSTRFcwM
    [SysAbiExport(
        Nid = "f0jfSTRFcwM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V122GetMatchDetailResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0902(CpuContext ctx) => Destruct(ctx, 21);
    // V44_EXPORT_END nid=f0jfSTRFcwM

    // V44_EXPORT_BEGIN nid=GGKYUO8eo4I
    [SysAbiExport(
        Nid = "GGKYUO8eo4I",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V116JoinMatchRequestC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0907(CpuContext ctx) => Construct(ctx, 22);
    // V44_EXPORT_END nid=GGKYUO8eo4I

    // V44_EXPORT_BEGIN nid=ZHvMrBTIkfU
    [SysAbiExport(
        Nid = "ZHvMrBTIkfU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V116JoinMatchRequestC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0908(CpuContext ctx) => Construct(ctx, 22);
    // V44_EXPORT_END nid=ZHvMrBTIkfU

    // V44_EXPORT_BEGIN nid=TNIVUy2LiBo
    [SysAbiExport(
        Nid = "TNIVUy2LiBo",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V116JoinMatchRequest17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0910(CpuContext ctx) => GetValue(ctx, 22, 55, ReturnKind.U32);
    // V44_EXPORT_END nid=TNIVUy2LiBo

    // V44_EXPORT_BEGIN nid=PKaqqJ0gWgM
    [SysAbiExport(
        Nid = "PKaqqJ0gWgM",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V116JoinMatchRequest19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0912(CpuContext ctx) => IsSet(ctx, 22, 55);
    // V44_EXPORT_END nid=PKaqqJ0gWgM

    // V44_EXPORT_BEGIN nid=CvQHe7rKZvI
    [SysAbiExport(
        Nid = "CvQHe7rKZvI",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V116JoinMatchRequest17setNpServiceLabelERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0913(CpuContext ctx) => SetValue(ctx, 22, 55, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=CvQHe7rKZvI

    // V44_EXPORT_BEGIN nid=dAZNLw22-cY
    [SysAbiExport(
        Nid = "dAZNLw22-cY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V116JoinMatchRequest19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0916(CpuContext ctx) => Unset(ctx, 22, 55);
    // V44_EXPORT_END nid=dAZNLw22-cY

    // V44_EXPORT_BEGIN nid=bEeGSoRz+DI
    [SysAbiExport(
        Nid = "bEeGSoRz+DI",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V116JoinMatchRequestD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0917(CpuContext ctx) => Destruct(ctx, 22);
    // V44_EXPORT_END nid=bEeGSoRz+DI

    // V44_EXPORT_BEGIN nid=bzQSQiUzfVY
    [SysAbiExport(
        Nid = "bzQSQiUzfVY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V116JoinMatchRequestD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0918(CpuContext ctx) => Destruct(ctx, 22);
    // V44_EXPORT_END nid=bzQSQiUzfVY

    // V44_EXPORT_BEGIN nid=QVsYsUEgbHo
    [SysAbiExport(
        Nid = "QVsYsUEgbHo",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V117LeaveMatchRequestC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0922(CpuContext ctx) => Construct(ctx, 23);
    // V44_EXPORT_END nid=QVsYsUEgbHo

    // V44_EXPORT_BEGIN nid=biFFZqN9oGU
    [SysAbiExport(
        Nid = "biFFZqN9oGU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V117LeaveMatchRequestC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0923(CpuContext ctx) => Construct(ctx, 23);
    // V44_EXPORT_END nid=biFFZqN9oGU

    // V44_EXPORT_BEGIN nid=3SHDTB+hy4k
    [SysAbiExport(
        Nid = "3SHDTB+hy4k",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V117LeaveMatchRequest17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0925(CpuContext ctx) => GetValue(ctx, 23, 56, ReturnKind.U32);
    // V44_EXPORT_END nid=3SHDTB+hy4k

    // V44_EXPORT_BEGIN nid=MiLqYGxS1ck
    [SysAbiExport(
        Nid = "MiLqYGxS1ck",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V117LeaveMatchRequest19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0927(CpuContext ctx) => IsSet(ctx, 23, 56);
    // V44_EXPORT_END nid=MiLqYGxS1ck

    // V44_EXPORT_BEGIN nid=a4nA96ohus4
    [SysAbiExport(
        Nid = "a4nA96ohus4",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V117LeaveMatchRequest17setNpServiceLabelERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0928(CpuContext ctx) => SetValue(ctx, 23, 56, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=a4nA96ohus4

    // V44_EXPORT_BEGIN nid=7ItP6sEP+m0
    [SysAbiExport(
        Nid = "7ItP6sEP+m0",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V117LeaveMatchRequest19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0931(CpuContext ctx) => Unset(ctx, 23, 56);
    // V44_EXPORT_END nid=7ItP6sEP+m0

    // V44_EXPORT_BEGIN nid=-I22EAAA4uI
    [SysAbiExport(
        Nid = "-I22EAAA4uI",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V117LeaveMatchRequestD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0932(CpuContext ctx) => Destruct(ctx, 23);
    // V44_EXPORT_END nid=-I22EAAA4uI

    // V44_EXPORT_BEGIN nid=TMK1MOeUsO0
    [SysAbiExport(
        Nid = "TMK1MOeUsO0",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V117LeaveMatchRequestD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0933(CpuContext ctx) => Destruct(ctx, 23);
    // V44_EXPORT_END nid=TMK1MOeUsO0

    // V44_EXPORT_BEGIN nid=Wa9BXL+N09Q
    [SysAbiExport(
        Nid = "Wa9BXL+N09Q",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V18MatchApi25ParameterToGetMatchDetail17getnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0954(CpuContext ctx) => GetValue(ctx, 24, 57, ReturnKind.U32);
    // V44_EXPORT_END nid=Wa9BXL+N09Q

    // V44_EXPORT_BEGIN nid=Kh-g69HFYZ8
    [SysAbiExport(
        Nid = "Kh-g69HFYZ8",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V18MatchApi25ParameterToGetMatchDetail17hasnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0956(CpuContext ctx) => IsSet(ctx, 24, 57);
    // V44_EXPORT_END nid=Kh-g69HFYZ8

    // V44_EXPORT_BEGIN nid=KWEMMPMT56w
    [SysAbiExport(
        Nid = "KWEMMPMT56w",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V18MatchApi25ParameterToGetMatchDetail17setnpServiceLabelEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0962(CpuContext ctx) => SetValue(ctx, 24, 57, ValueSource.Register, false);
    // V44_EXPORT_END nid=KWEMMPMT56w

    // V44_EXPORT_BEGIN nid=1wsPC7RqShQ
    [SysAbiExport(
        Nid = "1wsPC7RqShQ",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V18MatchApi25ParameterToGetMatchDetail19unsetnpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0965(CpuContext ctx) => Unset(ctx, 24, 57);
    // V44_EXPORT_END nid=1wsPC7RqShQ

    // V44_EXPORT_BEGIN nid=Y0LQ0UrxiEs
    [SysAbiExport(
        Nid = "Y0LQ0UrxiEs",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V18MatchApi25ParameterToGetMatchDetailD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0967(CpuContext ctx) => Destruct(ctx, 24);
    // V44_EXPORT_END nid=Y0LQ0UrxiEs

    // V44_EXPORT_BEGIN nid=sPECNs8xNqs
    [SysAbiExport(
        Nid = "sPECNs8xNqs",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V18MatchApi25ParameterToGetMatchDetailD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api0968(CpuContext ctx) => Destruct(ctx, 24);
    // V44_EXPORT_END nid=sPECNs8xNqs

    // V44_EXPORT_BEGIN nid=99IBjvBYx88
    [SysAbiExport(
        Nid = "99IBjvBYx88",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120ReportResultsRequestC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1061(CpuContext ctx) => Construct(ctx, 25);
    // V44_EXPORT_END nid=99IBjvBYx88

    // V44_EXPORT_BEGIN nid=yaIK6PiubAE
    [SysAbiExport(
        Nid = "yaIK6PiubAE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120ReportResultsRequestC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1062(CpuContext ctx) => Construct(ctx, 25);
    // V44_EXPORT_END nid=yaIK6PiubAE

    // V44_EXPORT_BEGIN nid=tTImOZcDu4o
    [SysAbiExport(
        Nid = "tTImOZcDu4o",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V120ReportResultsRequest17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1066(CpuContext ctx) => GetValue(ctx, 25, 58, ReturnKind.U32);
    // V44_EXPORT_END nid=tTImOZcDu4o

    // V44_EXPORT_BEGIN nid=rvJ+IqRSAT4
    [SysAbiExport(
        Nid = "rvJ+IqRSAT4",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V120ReportResultsRequest19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1068(CpuContext ctx) => IsSet(ctx, 25, 58);
    // V44_EXPORT_END nid=rvJ+IqRSAT4

    // V44_EXPORT_BEGIN nid=hvaTjFV3IEU
    [SysAbiExport(
        Nid = "hvaTjFV3IEU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120ReportResultsRequest17setNpServiceLabelERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1071(CpuContext ctx) => SetValue(ctx, 25, 58, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=hvaTjFV3IEU

    // V44_EXPORT_BEGIN nid=zQRMb7uXGag
    [SysAbiExport(
        Nid = "zQRMb7uXGag",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120ReportResultsRequest19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1074(CpuContext ctx) => Unset(ctx, 25, 58);
    // V44_EXPORT_END nid=zQRMb7uXGag

    // V44_EXPORT_BEGIN nid=BLyDVSfU8a0
    [SysAbiExport(
        Nid = "BLyDVSfU8a0",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120ReportResultsRequestD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1075(CpuContext ctx) => Destruct(ctx, 25);
    // V44_EXPORT_END nid=BLyDVSfU8a0

    // V44_EXPORT_BEGIN nid=dqTyHmzAAAA
    [SysAbiExport(
        Nid = "dqTyHmzAAAA",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120ReportResultsRequestD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1076(CpuContext ctx) => Destruct(ctx, 25);
    // V44_EXPORT_END nid=dqTyHmzAAAA

    // V44_EXPORT_BEGIN nid=2VLqcPeTce8
    [SysAbiExport(
        Nid = "2VLqcPeTce8",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120RequestPlayerResultsC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1201(CpuContext ctx) => Construct(ctx, 26);
    // V44_EXPORT_END nid=2VLqcPeTce8

    // V44_EXPORT_BEGIN nid=jb6ic-qbD30
    [SysAbiExport(
        Nid = "jb6ic-qbD30",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120RequestPlayerResultsC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1202(CpuContext ctx) => Construct(ctx, 26);
    // V44_EXPORT_END nid=jb6ic-qbD30

    // V44_EXPORT_BEGIN nid=4vCyIflWano
    [SysAbiExport(
        Nid = "4vCyIflWano",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V120RequestPlayerResults7getRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1205(CpuContext ctx) => GetValue(ctx, 26, 59, ReturnKind.U32);
    // V44_EXPORT_END nid=4vCyIflWano

    // V44_EXPORT_BEGIN nid=WdK-Teg0wGs
    [SysAbiExport(
        Nid = "WdK-Teg0wGs",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V120RequestPlayerResults8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1206(CpuContext ctx) => GetValue(ctx, 26, 60, ReturnKind.Float64);
    // V44_EXPORT_END nid=WdK-Teg0wGs

    // V44_EXPORT_BEGIN nid=5SIn8558ccY
    [SysAbiExport(
        Nid = "5SIn8558ccY",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V120RequestPlayerResults10scoreIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1207(CpuContext ctx) => IsSet(ctx, 26, 60);
    // V44_EXPORT_END nid=5SIn8558ccY

    // V44_EXPORT_BEGIN nid=OxV2cTcE3xs
    [SysAbiExport(
        Nid = "OxV2cTcE3xs",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120RequestPlayerResults7setRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1209(CpuContext ctx) => SetValue(ctx, 26, 59, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=OxV2cTcE3xs

    // V44_EXPORT_BEGIN nid=GZxQA0G4NKY
    [SysAbiExport(
        Nid = "GZxQA0G4NKY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120RequestPlayerResults8setScoreERKd",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1210(CpuContext ctx) => SetValue(ctx, 26, 60, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=GZxQA0G4NKY

    // V44_EXPORT_BEGIN nid=mrHkGpzNlfM
    [SysAbiExport(
        Nid = "mrHkGpzNlfM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120RequestPlayerResults10unsetScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1212(CpuContext ctx) => Unset(ctx, 26, 60);
    // V44_EXPORT_END nid=mrHkGpzNlfM

    // V44_EXPORT_BEGIN nid=1Iz-n06N8C0
    [SysAbiExport(
        Nid = "1Iz-n06N8C0",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120RequestPlayerResultsD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1213(CpuContext ctx) => Destruct(ctx, 26);
    // V44_EXPORT_END nid=1Iz-n06N8C0

    // V44_EXPORT_BEGIN nid=wRgkEJFWGCY
    [SysAbiExport(
        Nid = "wRgkEJFWGCY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V120RequestPlayerResultsD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1214(CpuContext ctx) => Destruct(ctx, 26);
    // V44_EXPORT_END nid=wRgkEJFWGCY

    // V44_EXPORT_BEGIN nid=2lWQC5EWuzU
    [SysAbiExport(
        Nid = "2lWQC5EWuzU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V123RequestTeamMemberResultC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1231(CpuContext ctx) => Construct(ctx, 27);
    // V44_EXPORT_END nid=2lWQC5EWuzU

    // V44_EXPORT_BEGIN nid=bbZ0uWzshUA
    [SysAbiExport(
        Nid = "bbZ0uWzshUA",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V123RequestTeamMemberResultC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1232(CpuContext ctx) => Construct(ctx, 27);
    // V44_EXPORT_END nid=bbZ0uWzshUA

    // V44_EXPORT_BEGIN nid=qd1v-zYjor4
    [SysAbiExport(
        Nid = "qd1v-zYjor4",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V123RequestTeamMemberResult8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1235(CpuContext ctx) => GetValue(ctx, 27, 61, ReturnKind.Float64);
    // V44_EXPORT_END nid=qd1v-zYjor4

    // V44_EXPORT_BEGIN nid=82J08GIspUI
    [SysAbiExport(
        Nid = "82J08GIspUI",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V123RequestTeamMemberResult8setScoreERKd",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1237(CpuContext ctx) => SetValue(ctx, 27, 61, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=82J08GIspUI

    // V44_EXPORT_BEGIN nid=T6eEJ0yDotY
    [SysAbiExport(
        Nid = "T6eEJ0yDotY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V123RequestTeamMemberResultD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1239(CpuContext ctx) => Destruct(ctx, 27);
    // V44_EXPORT_END nid=T6eEJ0yDotY

    // V44_EXPORT_BEGIN nid=nfyoqm6zlBI
    [SysAbiExport(
        Nid = "nfyoqm6zlBI",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V123RequestTeamMemberResultD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1240(CpuContext ctx) => Destruct(ctx, 27);
    // V44_EXPORT_END nid=nfyoqm6zlBI

    // V44_EXPORT_BEGIN nid=k3B5vS6IiKA
    [SysAbiExport(
        Nid = "k3B5vS6IiKA",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118RequestTeamResultsC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1257(CpuContext ctx) => Construct(ctx, 28);
    // V44_EXPORT_END nid=k3B5vS6IiKA

    // V44_EXPORT_BEGIN nid=kaGqLGDNa0Y
    [SysAbiExport(
        Nid = "kaGqLGDNa0Y",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118RequestTeamResultsC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1258(CpuContext ctx) => Construct(ctx, 28);
    // V44_EXPORT_END nid=kaGqLGDNa0Y

    // V44_EXPORT_BEGIN nid=11uEI36hbmA
    [SysAbiExport(
        Nid = "11uEI36hbmA",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118RequestTeamResults7getRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1260(CpuContext ctx) => GetValue(ctx, 28, 62, ReturnKind.U32);
    // V44_EXPORT_END nid=11uEI36hbmA

    // V44_EXPORT_BEGIN nid=4UWDiU1sWU0
    [SysAbiExport(
        Nid = "4UWDiU1sWU0",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118RequestTeamResults8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1261(CpuContext ctx) => GetValue(ctx, 28, 63, ReturnKind.Float64);
    // V44_EXPORT_END nid=4UWDiU1sWU0

    // V44_EXPORT_BEGIN nid=EdkISCe7zb8
    [SysAbiExport(
        Nid = "EdkISCe7zb8",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V118RequestTeamResults10scoreIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1264(CpuContext ctx) => IsSet(ctx, 28, 63);
    // V44_EXPORT_END nid=EdkISCe7zb8

    // V44_EXPORT_BEGIN nid=ubJZVBCQFgk
    [SysAbiExport(
        Nid = "ubJZVBCQFgk",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118RequestTeamResults7setRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1265(CpuContext ctx) => SetValue(ctx, 28, 62, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=ubJZVBCQFgk

    // V44_EXPORT_BEGIN nid=fdwMUgaSJ7A
    [SysAbiExport(
        Nid = "fdwMUgaSJ7A",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118RequestTeamResults8setScoreERKd",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1266(CpuContext ctx) => SetValue(ctx, 28, 63, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=fdwMUgaSJ7A

    // V44_EXPORT_BEGIN nid=NBymTwgR3WQ
    [SysAbiExport(
        Nid = "NBymTwgR3WQ",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118RequestTeamResults10unsetScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1271(CpuContext ctx) => Unset(ctx, 28, 63);
    // V44_EXPORT_END nid=NBymTwgR3WQ

    // V44_EXPORT_BEGIN nid=7DhQVaOVB0E
    [SysAbiExport(
        Nid = "7DhQVaOVB0E",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118RequestTeamResultsD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1273(CpuContext ctx) => Destruct(ctx, 28);
    // V44_EXPORT_END nid=7DhQVaOVB0E

    // V44_EXPORT_BEGIN nid=udmos65cRQo
    [SysAbiExport(
        Nid = "udmos65cRQo",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V118RequestTeamResultsD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1274(CpuContext ctx) => Destruct(ctx, 28);
    // V44_EXPORT_END nid=udmos65cRQo

    // V44_EXPORT_BEGIN nid=IPF05cGyxsY
    [SysAbiExport(
        Nid = "IPF05cGyxsY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResultsC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1327(CpuContext ctx) => Construct(ctx, 29);
    // V44_EXPORT_END nid=IPF05cGyxsY

    // V44_EXPORT_BEGIN nid=wjlHlTsAt9I
    [SysAbiExport(
        Nid = "wjlHlTsAt9I",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResultsC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1328(CpuContext ctx) => Construct(ctx, 29);
    // V44_EXPORT_END nid=wjlHlTsAt9I

    // V44_EXPORT_BEGIN nid=YPZRhrnAUH0
    [SysAbiExport(
        Nid = "YPZRhrnAUH0",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResults7getRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1330(CpuContext ctx) => GetValue(ctx, 29, 64, ReturnKind.U32);
    // V44_EXPORT_END nid=YPZRhrnAUH0

    // V44_EXPORT_BEGIN nid=PRWDDCYpsDQ
    [SysAbiExport(
        Nid = "PRWDDCYpsDQ",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResults8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1331(CpuContext ctx) => GetValue(ctx, 29, 65, ReturnKind.Float64);
    // V44_EXPORT_END nid=PRWDDCYpsDQ

    // V44_EXPORT_BEGIN nid=KA56yfHRZ0M
    [SysAbiExport(
        Nid = "KA56yfHRZ0M",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResults10scoreIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1334(CpuContext ctx) => IsSet(ctx, 29, 65);
    // V44_EXPORT_END nid=KA56yfHRZ0M

    // V44_EXPORT_BEGIN nid=iB+3lLjBUm4
    [SysAbiExport(
        Nid = "iB+3lLjBUm4",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResults7setRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1335(CpuContext ctx) => SetValue(ctx, 29, 64, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=iB+3lLjBUm4

    // V44_EXPORT_BEGIN nid=CAM9NbC8Jus
    [SysAbiExport(
        Nid = "CAM9NbC8Jus",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResults8setScoreERKd",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1336(CpuContext ctx) => SetValue(ctx, 29, 65, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=CAM9NbC8Jus

    // V44_EXPORT_BEGIN nid=h7UWAc6+MEE
    [SysAbiExport(
        Nid = "h7UWAc6+MEE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResults10unsetScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1341(CpuContext ctx) => Unset(ctx, 29, 65);
    // V44_EXPORT_END nid=h7UWAc6+MEE

    // V44_EXPORT_BEGIN nid=+lpzZ5UmZRc
    [SysAbiExport(
        Nid = "+lpzZ5UmZRc",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResultsD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1343(CpuContext ctx) => Destruct(ctx, 29);
    // V44_EXPORT_END nid=+lpzZ5UmZRc

    // V44_EXPORT_BEGIN nid=gLTNH0EWMic
    [SysAbiExport(
        Nid = "gLTNH0EWMic",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V127RequestTemporaryTeamResultsD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1344(CpuContext ctx) => Destruct(ctx, 29);
    // V44_EXPORT_END nid=gLTNH0EWMic

    // V44_EXPORT_BEGIN nid=Ba7cIC6zfKE
    [SysAbiExport(
        Nid = "Ba7cIC6zfKE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseMatchPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1382(CpuContext ctx) => Construct(ctx, 30);
    // V44_EXPORT_END nid=Ba7cIC6zfKE

    // V44_EXPORT_BEGIN nid=fpz1nROvElc
    [SysAbiExport(
        Nid = "fpz1nROvElc",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseMatchPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1383(CpuContext ctx) => Construct(ctx, 30);
    // V44_EXPORT_END nid=fpz1nROvElc

    // V44_EXPORT_BEGIN nid=LAtHDO4YPVc
    [SysAbiExport(
        Nid = "LAtHDO4YPVc",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V119ResponseMatchPlayer11getJoinFlagEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1387(CpuContext ctx) => GetValue(ctx, 30, 66, ReturnKind.Bool);
    // V44_EXPORT_END nid=LAtHDO4YPVc

    // V44_EXPORT_BEGIN nid=o8uz5K-EbR0
    [SysAbiExport(
        Nid = "o8uz5K-EbR0",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseMatchPlayer11setJoinFlagERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1395(CpuContext ctx) => SetValue(ctx, 30, 66, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=o8uz5K-EbR0

    // V44_EXPORT_BEGIN nid=7sC0PWT-6x8
    [SysAbiExport(
        Nid = "7sC0PWT-6x8",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseMatchPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1404(CpuContext ctx) => Destruct(ctx, 30);
    // V44_EXPORT_END nid=7sC0PWT-6x8

    // V44_EXPORT_BEGIN nid=JDLZ8x9gcVc
    [SysAbiExport(
        Nid = "JDLZ8x9gcVc",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseMatchPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1405(CpuContext ctx) => Destruct(ctx, 30);
    // V44_EXPORT_END nid=JDLZ8x9gcVc

    // V44_EXPORT_BEGIN nid=7R65C8WTc9E
    [SysAbiExport(
        Nid = "7R65C8WTc9E",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V114ResponseMemberC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1464(CpuContext ctx) => Construct(ctx, 31);
    // V44_EXPORT_END nid=7R65C8WTc9E

    // V44_EXPORT_BEGIN nid=TO8m+qmr3KM
    [SysAbiExport(
        Nid = "TO8m+qmr3KM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V114ResponseMemberC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1465(CpuContext ctx) => Construct(ctx, 31);
    // V44_EXPORT_END nid=TO8m+qmr3KM

    // V44_EXPORT_BEGIN nid=cmVpl3RY18M
    [SysAbiExport(
        Nid = "cmVpl3RY18M",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V114ResponseMember11getJoinFlagEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1467(CpuContext ctx) => GetValue(ctx, 31, 67, ReturnKind.Bool);
    // V44_EXPORT_END nid=cmVpl3RY18M

    // V44_EXPORT_BEGIN nid=5a9GgEplHSU
    [SysAbiExport(
        Nid = "5a9GgEplHSU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V114ResponseMember11setJoinFlagERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1469(CpuContext ctx) => SetValue(ctx, 31, 67, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=5a9GgEplHSU

    // V44_EXPORT_BEGIN nid=F8BjVmFyYLg
    [SysAbiExport(
        Nid = "F8BjVmFyYLg",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V114ResponseMemberD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1472(CpuContext ctx) => Destruct(ctx, 31);
    // V44_EXPORT_END nid=F8BjVmFyYLg

    // V44_EXPORT_BEGIN nid=tXhczWuQIls
    [SysAbiExport(
        Nid = "tXhczWuQIls",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V114ResponseMemberD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1473(CpuContext ctx) => Destruct(ctx, 31);
    // V44_EXPORT_END nid=tXhczWuQIls

    // V44_EXPORT_BEGIN nid=QctMzHHZSfc
    [SysAbiExport(
        Nid = "QctMzHHZSfc",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V121ResponsePlayerResultsC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1477(CpuContext ctx) => Construct(ctx, 32);
    // V44_EXPORT_END nid=QctMzHHZSfc

    // V44_EXPORT_BEGIN nid=WE0-4xvquLU
    [SysAbiExport(
        Nid = "WE0-4xvquLU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V121ResponsePlayerResultsC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1478(CpuContext ctx) => Construct(ctx, 32);
    // V44_EXPORT_END nid=WE0-4xvquLU

    // V44_EXPORT_BEGIN nid=wuettmP-HHY
    [SysAbiExport(
        Nid = "wuettmP-HHY",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V121ResponsePlayerResults7getRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1481(CpuContext ctx) => GetValue(ctx, 32, 68, ReturnKind.U32);
    // V44_EXPORT_END nid=wuettmP-HHY

    // V44_EXPORT_BEGIN nid=hulfhT-chcs
    [SysAbiExport(
        Nid = "hulfhT-chcs",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V121ResponsePlayerResults8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1482(CpuContext ctx) => GetValue(ctx, 32, 69, ReturnKind.Float64);
    // V44_EXPORT_END nid=hulfhT-chcs

    // V44_EXPORT_BEGIN nid=Erp13lgq9JM
    [SysAbiExport(
        Nid = "Erp13lgq9JM",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V121ResponsePlayerResults10scoreIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1483(CpuContext ctx) => IsSet(ctx, 32, 69);
    // V44_EXPORT_END nid=Erp13lgq9JM

    // V44_EXPORT_BEGIN nid=UScMQLt-6I0
    [SysAbiExport(
        Nid = "UScMQLt-6I0",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V121ResponsePlayerResults7setRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1485(CpuContext ctx) => SetValue(ctx, 32, 68, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=UScMQLt-6I0

    // V44_EXPORT_BEGIN nid=bTEm3XhQmzk
    [SysAbiExport(
        Nid = "bTEm3XhQmzk",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V121ResponsePlayerResults8setScoreERKd",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1486(CpuContext ctx) => SetValue(ctx, 32, 69, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=bTEm3XhQmzk

    // V44_EXPORT_BEGIN nid=c53FpjaR+Lo
    [SysAbiExport(
        Nid = "c53FpjaR+Lo",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V121ResponsePlayerResults10unsetScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1488(CpuContext ctx) => Unset(ctx, 32, 69);
    // V44_EXPORT_END nid=c53FpjaR+Lo

    // V44_EXPORT_BEGIN nid=M8pHNPzTrBU
    [SysAbiExport(
        Nid = "M8pHNPzTrBU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V121ResponsePlayerResultsD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1489(CpuContext ctx) => Destruct(ctx, 32);
    // V44_EXPORT_END nid=M8pHNPzTrBU

    // V44_EXPORT_BEGIN nid=cl+f5DIiOUk
    [SysAbiExport(
        Nid = "cl+f5DIiOUk",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V121ResponsePlayerResultsD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1490(CpuContext ctx) => Destruct(ctx, 32);
    // V44_EXPORT_END nid=cl+f5DIiOUk

    // V44_EXPORT_BEGIN nid=3x4Zf5kAezE
    [SysAbiExport(
        Nid = "3x4Zf5kAezE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124ResponseTeamMemberResultC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1507(CpuContext ctx) => Construct(ctx, 33);
    // V44_EXPORT_END nid=3x4Zf5kAezE

    // V44_EXPORT_BEGIN nid=Srhc9BV4BTk
    [SysAbiExport(
        Nid = "Srhc9BV4BTk",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124ResponseTeamMemberResultC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1508(CpuContext ctx) => Construct(ctx, 33);
    // V44_EXPORT_END nid=Srhc9BV4BTk

    // V44_EXPORT_BEGIN nid=L0aobPyYBRw
    [SysAbiExport(
        Nid = "L0aobPyYBRw",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V124ResponseTeamMemberResult8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1511(CpuContext ctx) => GetValue(ctx, 33, 70, ReturnKind.Float64);
    // V44_EXPORT_END nid=L0aobPyYBRw

    // V44_EXPORT_BEGIN nid=r3dWNxl4X-g
    [SysAbiExport(
        Nid = "r3dWNxl4X-g",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124ResponseTeamMemberResult8setScoreERKd",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1513(CpuContext ctx) => SetValue(ctx, 33, 70, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=r3dWNxl4X-g

    // V44_EXPORT_BEGIN nid=4tUowCWwdyI
    [SysAbiExport(
        Nid = "4tUowCWwdyI",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124ResponseTeamMemberResultD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1515(CpuContext ctx) => Destruct(ctx, 33);
    // V44_EXPORT_END nid=4tUowCWwdyI

    // V44_EXPORT_BEGIN nid=5rrJMdrBV0g
    [SysAbiExport(
        Nid = "5rrJMdrBV0g",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124ResponseTeamMemberResultD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1516(CpuContext ctx) => Destruct(ctx, 33);
    // V44_EXPORT_END nid=5rrJMdrBV0g

    // V44_EXPORT_BEGIN nid=5Jowi8NzZIs
    [SysAbiExport(
        Nid = "5Jowi8NzZIs",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseTeamResultsC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1533(CpuContext ctx) => Construct(ctx, 34);
    // V44_EXPORT_END nid=5Jowi8NzZIs

    // V44_EXPORT_BEGIN nid=Yhij947AtOU
    [SysAbiExport(
        Nid = "Yhij947AtOU",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseTeamResultsC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1534(CpuContext ctx) => Construct(ctx, 34);
    // V44_EXPORT_END nid=Yhij947AtOU

    // V44_EXPORT_BEGIN nid=U3xnMqYSrnA
    [SysAbiExport(
        Nid = "U3xnMqYSrnA",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V119ResponseTeamResults7getRankEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1536(CpuContext ctx) => GetValue(ctx, 34, 71, ReturnKind.U32);
    // V44_EXPORT_END nid=U3xnMqYSrnA

    // V44_EXPORT_BEGIN nid=qUziNVrQ+wo
    [SysAbiExport(
        Nid = "qUziNVrQ+wo",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V119ResponseTeamResults8getScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1537(CpuContext ctx) => GetValue(ctx, 34, 72, ReturnKind.Float64);
    // V44_EXPORT_END nid=qUziNVrQ+wo

    // V44_EXPORT_BEGIN nid=ypQ1+CIeMQ4
    [SysAbiExport(
        Nid = "ypQ1+CIeMQ4",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V119ResponseTeamResults10scoreIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1540(CpuContext ctx) => IsSet(ctx, 34, 72);
    // V44_EXPORT_END nid=ypQ1+CIeMQ4

    // V44_EXPORT_BEGIN nid=-eu869E6GrY
    [SysAbiExport(
        Nid = "-eu869E6GrY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseTeamResults7setRankERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1541(CpuContext ctx) => SetValue(ctx, 34, 71, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=-eu869E6GrY

    // V44_EXPORT_BEGIN nid=EnehEnuAhVo
    [SysAbiExport(
        Nid = "EnehEnuAhVo",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseTeamResults8setScoreERKd",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1542(CpuContext ctx) => SetValue(ctx, 34, 72, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=EnehEnuAhVo

    // V44_EXPORT_BEGIN nid=ewYyfU0X-QM
    [SysAbiExport(
        Nid = "ewYyfU0X-QM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseTeamResults10unsetScoreEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1547(CpuContext ctx) => Unset(ctx, 34, 72);
    // V44_EXPORT_END nid=ewYyfU0X-QM

    // V44_EXPORT_BEGIN nid=WY8bn42LPDw
    [SysAbiExport(
        Nid = "WY8bn42LPDw",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseTeamResultsD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1549(CpuContext ctx) => Destruct(ctx, 34);
    // V44_EXPORT_END nid=WY8bn42LPDw

    // V44_EXPORT_BEGIN nid=ea-aQUt8eaE
    [SysAbiExport(
        Nid = "ea-aQUt8eaE",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V119ResponseTeamResultsD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1550(CpuContext ctx) => Destruct(ctx, 34);
    // V44_EXPORT_END nid=ea-aQUt8eaE

    // V44_EXPORT_BEGIN nid=X67RLMWgJC0
    [SysAbiExport(
        Nid = "X67RLMWgJC0",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequestC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1607(CpuContext ctx) => Construct(ctx, 35);
    // V44_EXPORT_END nid=X67RLMWgJC0

    // V44_EXPORT_BEGIN nid=fi0TIYERtsY
    [SysAbiExport(
        Nid = "fi0TIYERtsY",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequestC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1608(CpuContext ctx) => Construct(ctx, 35);
    // V44_EXPORT_END nid=fi0TIYERtsY

    // V44_EXPORT_BEGIN nid=IxPxVmr12vk
    [SysAbiExport(
        Nid = "IxPxVmr12vk",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest19expirationTimeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1611(CpuContext ctx) => IsSet(ctx, 35, 73);
    // V44_EXPORT_END nid=IxPxVmr12vk

    // V44_EXPORT_BEGIN nid=lH87l00Fyq0
    [SysAbiExport(
        Nid = "lH87l00Fyq0",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest17getExpirationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1615(CpuContext ctx) => GetValue(ctx, 35, 73, ReturnKind.U32);
    // V44_EXPORT_END nid=lH87l00Fyq0

    // V44_EXPORT_BEGIN nid=kBj79hWFelk
    [SysAbiExport(
        Nid = "kBj79hWFelk",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1619(CpuContext ctx) => GetValue(ctx, 35, 74, ReturnKind.U32);
    // V44_EXPORT_END nid=kBj79hWFelk

    // V44_EXPORT_BEGIN nid=wIZEfsXrrxA
    [SysAbiExport(
        Nid = "wIZEfsXrrxA",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1624(CpuContext ctx) => IsSet(ctx, 35, 74);
    // V44_EXPORT_END nid=wIZEfsXrrxA

    // V44_EXPORT_BEGIN nid=QxatxkNYNls
    [SysAbiExport(
        Nid = "QxatxkNYNls",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest17setExpirationTimeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1627(CpuContext ctx) => SetValue(ctx, 35, 73, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=QxatxkNYNls

    // V44_EXPORT_BEGIN nid=mV3PKml1+B4
    [SysAbiExport(
        Nid = "mV3PKml1+B4",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest17setNpServiceLabelERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1631(CpuContext ctx) => SetValue(ctx, 35, 74, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=mV3PKml1+B4

    // V44_EXPORT_BEGIN nid=L4J2kYpZ9vo
    [SysAbiExport(
        Nid = "L4J2kYpZ9vo",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest19unsetExpirationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1636(CpuContext ctx) => Unset(ctx, 35, 73);
    // V44_EXPORT_END nid=L4J2kYpZ9vo

    // V44_EXPORT_BEGIN nid=MkccIFpDqzM
    [SysAbiExport(
        Nid = "MkccIFpDqzM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequest19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1640(CpuContext ctx) => Unset(ctx, 35, 74);
    // V44_EXPORT_END nid=MkccIFpDqzM

    // V44_EXPORT_BEGIN nid=Naoh3hA7F7g
    [SysAbiExport(
        Nid = "Naoh3hA7F7g",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequestD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1643(CpuContext ctx) => Destruct(ctx, 35);
    // V44_EXPORT_END nid=Naoh3hA7F7g

    // V44_EXPORT_BEGIN nid=XkgQotEtIhI
    [SysAbiExport(
        Nid = "XkgQotEtIhI",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchDetailRequestD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1644(CpuContext ctx) => Destruct(ctx, 35);
    // V44_EXPORT_END nid=XkgQotEtIhI

    // V44_EXPORT_BEGIN nid=15vmGXiUnGw
    [SysAbiExport(
        Nid = "15vmGXiUnGw",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequestC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1648(CpuContext ctx) => Construct(ctx, 36);
    // V44_EXPORT_END nid=15vmGXiUnGw

    // V44_EXPORT_BEGIN nid=2X7awcQsJms
    [SysAbiExport(
        Nid = "2X7awcQsJms",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequestC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1649(CpuContext ctx) => Construct(ctx, 36);
    // V44_EXPORT_END nid=2X7awcQsJms

    // V44_EXPORT_BEGIN nid=Z-6Uqn78290
    [SysAbiExport(
        Nid = "Z-6Uqn78290",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequest17getNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1651(CpuContext ctx) => GetValue(ctx, 36, 75, ReturnKind.U32);
    // V44_EXPORT_END nid=Z-6Uqn78290

    // V44_EXPORT_BEGIN nid=Nmy96vm1DwM
    [SysAbiExport(
        Nid = "Nmy96vm1DwM",
        ExportName = "_ZNK3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequest19npServiceLabelIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1653(CpuContext ctx) => IsSet(ctx, 36, 75);
    // V44_EXPORT_END nid=Nmy96vm1DwM

    // V44_EXPORT_BEGIN nid=qbG3dvn-Qvo
    [SysAbiExport(
        Nid = "qbG3dvn-Qvo",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequest17setNpServiceLabelERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1654(CpuContext ctx) => SetValue(ctx, 36, 75, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=qbG3dvn-Qvo

    // V44_EXPORT_BEGIN nid=LrfNXipg+GM
    [SysAbiExport(
        Nid = "LrfNXipg+GM",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequest19unsetNpServiceLabelEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1657(CpuContext ctx) => Unset(ctx, 36, 75);
    // V44_EXPORT_END nid=LrfNXipg+GM

    // V44_EXPORT_BEGIN nid=c7w7pgkXH4Q
    [SysAbiExport(
        Nid = "c7w7pgkXH4Q",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequestD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1658(CpuContext ctx) => Destruct(ctx, 36);
    // V44_EXPORT_END nid=c7w7pgkXH4Q

    // V44_EXPORT_BEGIN nid=dJ-gAyxuEZo
    [SysAbiExport(
        Nid = "dJ-gAyxuEZo",
        ExportName = "_ZN3sce2Np9CppWebApi7Matches2V124UpdateMatchStatusRequestD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1659(CpuContext ctx) => Destruct(ctx, 36);
    // V44_EXPORT_END nid=dJ-gAyxuEZo

    // V44_EXPORT_BEGIN nid=+JCs2IrB7Lc
    [SysAbiExport(
        Nid = "+JCs2IrB7Lc",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15CauseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1775(CpuContext ctx) => Construct(ctx, 37);
    // V44_EXPORT_END nid=+JCs2IrB7Lc

    // V44_EXPORT_BEGIN nid=IpWmqKEuLxU
    [SysAbiExport(
        Nid = "IpWmqKEuLxU",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15CauseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1776(CpuContext ctx) => Construct(ctx, 37);
    // V44_EXPORT_END nid=IpWmqKEuLxU

    // V44_EXPORT_BEGIN nid=wdNyuvN52Q4
    [SysAbiExport(
        Nid = "wdNyuvN52Q4",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V15Cause9codeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1777(CpuContext ctx) => IsSet(ctx, 37, 76);
    // V44_EXPORT_END nid=wdNyuvN52Q4

    // V44_EXPORT_BEGIN nid=SxAScmvLxSM
    [SysAbiExport(
        Nid = "SxAScmvLxSM",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V15Cause7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1779(CpuContext ctx) => GetValue(ctx, 37, 76, ReturnKind.U64);
    // V44_EXPORT_END nid=SxAScmvLxSM

    // V44_EXPORT_BEGIN nid=Z5NW0XEH1hQ
    [SysAbiExport(
        Nid = "Z5NW0XEH1hQ",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15Cause7setCodeERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1783(CpuContext ctx) => SetValue(ctx, 37, 76, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=Z5NW0XEH1hQ

    // V44_EXPORT_BEGIN nid=kGjL8v4KTxM
    [SysAbiExport(
        Nid = "kGjL8v4KTxM",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15Cause9unsetCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1788(CpuContext ctx) => Unset(ctx, 37, 76);
    // V44_EXPORT_END nid=kGjL8v4KTxM

    // V44_EXPORT_BEGIN nid=E36Wp0SYd08
    [SysAbiExport(
        Nid = "E36Wp0SYd08",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15CauseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1791(CpuContext ctx) => Destruct(ctx, 37);
    // V44_EXPORT_END nid=E36Wp0SYd08

    // V44_EXPORT_BEGIN nid=TyArPzU-zOw
    [SysAbiExport(
        Nid = "TyArPzU-zOw",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15CauseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1792(CpuContext ctx) => Destruct(ctx, 37);
    // V44_EXPORT_END nid=TyArPzU-zOw

    // V44_EXPORT_BEGIN nid=6qy4F-nOeqI
    [SysAbiExport(
        Nid = "6qy4F-nOeqI",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1796(CpuContext ctx) => Construct(ctx, 38);
    // V44_EXPORT_END nid=6qy4F-nOeqI

    // V44_EXPORT_BEGIN nid=dsqwMNebbSw
    [SysAbiExport(
        Nid = "dsqwMNebbSw",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1797(CpuContext ctx) => Construct(ctx, 38);
    // V44_EXPORT_END nid=dsqwMNebbSw

    // V44_EXPORT_BEGIN nid=ss1xGhJRunI
    [SysAbiExport(
        Nid = "ss1xGhJRunI",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V15Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1799(CpuContext ctx) => GetValue(ctx, 38, 77, ReturnKind.U64);
    // V44_EXPORT_END nid=ss1xGhJRunI

    // V44_EXPORT_BEGIN nid=TrobtFJRMl0
    [SysAbiExport(
        Nid = "TrobtFJRMl0",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15Error7setCodeERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1802(CpuContext ctx) => SetValue(ctx, 38, 77, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=TrobtFJRMl0

    // V44_EXPORT_BEGIN nid=79k9QVa88ys
    [SysAbiExport(
        Nid = "79k9QVa88ys",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1806(CpuContext ctx) => Destruct(ctx, 38);
    // V44_EXPORT_END nid=79k9QVa88ys

    // V44_EXPORT_BEGIN nid=VqAPI9ZTizI
    [SysAbiExport(
        Nid = "VqAPI9ZTizI",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V15ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1807(CpuContext ctx) => Destruct(ctx, 38);
    // V44_EXPORT_END nid=VqAPI9ZTizI

    // V44_EXPORT_BEGIN nid=a4DFYgQfWNI
    [SysAbiExport(
        Nid = "a4DFYgQfWNI",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferReadC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1940(CpuContext ctx) => Construct(ctx, 39);
    // V44_EXPORT_END nid=a4DFYgQfWNI

    // V44_EXPORT_BEGIN nid=f7aBx5Yh-XA
    [SysAbiExport(
        Nid = "f7aBx5Yh-XA",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferReadC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1941(CpuContext ctx) => Construct(ctx, 39);
    // V44_EXPORT_END nid=f7aBx5Yh-XA

    // V44_EXPORT_BEGIN nid=YzMVqTigiyc
    [SysAbiExport(
        Nid = "YzMVqTigiyc",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferRead14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1942(CpuContext ctx) => IsSet(ctx, 39, 78);
    // V44_EXPORT_END nid=YzMVqTigiyc

    // V44_EXPORT_BEGIN nid=PfBVKm1Magc
    [SysAbiExport(
        Nid = "PfBVKm1Magc",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferRead12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1944(CpuContext ctx) => GetValue(ctx, 39, 78, ReturnKind.U64);
    // V44_EXPORT_END nid=PfBVKm1Magc

    // V44_EXPORT_BEGIN nid=RZQxMzPVW-E
    [SysAbiExport(
        Nid = "RZQxMzPVW-E",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferRead12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1951(CpuContext ctx) => SetValue(ctx, 39, 78, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=RZQxMzPVW-E

    // V44_EXPORT_BEGIN nid=RONWit6P118
    [SysAbiExport(
        Nid = "RONWit6P118",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferRead14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1959(CpuContext ctx) => Unset(ctx, 39, 78);
    // V44_EXPORT_END nid=RONWit6P118

    // V44_EXPORT_BEGIN nid=QXdPjIdqfxQ
    [SysAbiExport(
        Nid = "QXdPjIdqfxQ",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferReadD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1964(CpuContext ctx) => Destruct(ctx, 39);
    // V44_EXPORT_END nid=QXdPjIdqfxQ

    // V44_EXPORT_BEGIN nid=l1dzHWw0l8k
    [SysAbiExport(
        Nid = "l1dzHWw0l8k",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V118PlayerForOfferReadD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1965(CpuContext ctx) => Destruct(ctx, 39);
    // V44_EXPORT_END nid=l1dzHWw0l8k

    // V44_EXPORT_BEGIN nid=EmRD5jXfyyc
    [SysAbiExport(
        Nid = "EmRD5jXfyyc",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForReadC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1969(CpuContext ctx) => Construct(ctx, 40);
    // V44_EXPORT_END nid=EmRD5jXfyyc

    // V44_EXPORT_BEGIN nid=nRsDOZGMclk
    [SysAbiExport(
        Nid = "nRsDOZGMclk",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForReadC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1970(CpuContext ctx) => Construct(ctx, 40);
    // V44_EXPORT_END nid=nRsDOZGMclk

    // V44_EXPORT_BEGIN nid=7iX8e9aZI3Y
    [SysAbiExport(
        Nid = "7iX8e9aZI3Y",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1971(CpuContext ctx) => IsSet(ctx, 40, 79);
    // V44_EXPORT_END nid=7iX8e9aZI3Y

    // V44_EXPORT_BEGIN nid=crYcq1HKdq8
    [SysAbiExport(
        Nid = "crYcq1HKdq8",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1973(CpuContext ctx) => GetValue(ctx, 40, 79, ReturnKind.U64);
    // V44_EXPORT_END nid=crYcq1HKdq8

    // V44_EXPORT_BEGIN nid=SNwqnx6r3c8
    [SysAbiExport(
        Nid = "SNwqnx6r3c8",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1974(CpuContext ctx) => GetValue(ctx, 40, 80, ReturnKind.U32);
    // V44_EXPORT_END nid=SNwqnx6r3c8

    // V44_EXPORT_BEGIN nid=G29jd4UdmU8
    [SysAbiExport(
        Nid = "G29jd4UdmU8",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1979(CpuContext ctx) => IsSet(ctx, 40, 80);
    // V44_EXPORT_END nid=G29jd4UdmU8

    // V44_EXPORT_BEGIN nid=YnFogi5vqFs
    [SysAbiExport(
        Nid = "YnFogi5vqFs",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1983(CpuContext ctx) => SetValue(ctx, 40, 79, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=YnFogi5vqFs

    // V44_EXPORT_BEGIN nid=UmNOWVCFFCM
    [SysAbiExport(
        Nid = "UmNOWVCFFCM",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1984(CpuContext ctx) => SetValue(ctx, 40, 80, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=UmNOWVCFFCM

    // V44_EXPORT_BEGIN nid=PLisNcatYEU
    [SysAbiExport(
        Nid = "PLisNcatYEU",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1991(CpuContext ctx) => Unset(ctx, 40, 79);
    // V44_EXPORT_END nid=PLisNcatYEU

    // V44_EXPORT_BEGIN nid=XoC1V7O78uQ
    [SysAbiExport(
        Nid = "XoC1V7O78uQ",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForRead12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1992(CpuContext ctx) => Unset(ctx, 40, 80);
    // V44_EXPORT_END nid=XoC1V7O78uQ

    // V44_EXPORT_BEGIN nid=4F-9eVaDVCc
    [SysAbiExport(
        Nid = "4F-9eVaDVCc",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForReadD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1997(CpuContext ctx) => Destruct(ctx, 40);
    // V44_EXPORT_END nid=4F-9eVaDVCc

    // V44_EXPORT_BEGIN nid=846dTS0lJxA
    [SysAbiExport(
        Nid = "846dTS0lJxA",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V113PlayerForReadD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api1998(CpuContext ctx) => Destruct(ctx, 40);
    // V44_EXPORT_END nid=846dTS0lJxA

    // V44_EXPORT_BEGIN nid=RP-uCQo2rpo
    [SysAbiExport(
        Nid = "RP-uCQo2rpo",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreateC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2002(CpuContext ctx) => Construct(ctx, 41);
    // V44_EXPORT_END nid=RP-uCQo2rpo

    // V44_EXPORT_BEGIN nid=lQwRkOw4TaI
    [SysAbiExport(
        Nid = "lQwRkOw4TaI",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreateC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2003(CpuContext ctx) => Construct(ctx, 41);
    // V44_EXPORT_END nid=lQwRkOw4TaI

    // V44_EXPORT_BEGIN nid=CAeLxSO6Fzw
    [SysAbiExport(
        Nid = "CAeLxSO6Fzw",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreate12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2005(CpuContext ctx) => GetValue(ctx, 41, 81, ReturnKind.U64);
    // V44_EXPORT_END nid=CAeLxSO6Fzw

    // V44_EXPORT_BEGIN nid=E2QjFehvp2Y
    [SysAbiExport(
        Nid = "E2QjFehvp2Y",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreate10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2006(CpuContext ctx) => GetValue(ctx, 41, 82, ReturnKind.U32);
    // V44_EXPORT_END nid=E2QjFehvp2Y

    // V44_EXPORT_BEGIN nid=Oqfphi8E-Hc
    [SysAbiExport(
        Nid = "Oqfphi8E-Hc",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreate12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2010(CpuContext ctx) => IsSet(ctx, 41, 82);
    // V44_EXPORT_END nid=Oqfphi8E-Hc

    // V44_EXPORT_BEGIN nid=eG0qIomiwK0
    [SysAbiExport(
        Nid = "eG0qIomiwK0",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreate12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2012(CpuContext ctx) => SetValue(ctx, 41, 81, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=eG0qIomiwK0

    // V44_EXPORT_BEGIN nid=hH9TSsVNT74
    [SysAbiExport(
        Nid = "hH9TSsVNT74",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreate10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2013(CpuContext ctx) => SetValue(ctx, 41, 82, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=hH9TSsVNT74

    // V44_EXPORT_BEGIN nid=HRBeLG106ww
    [SysAbiExport(
        Nid = "HRBeLG106ww",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreate12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2019(CpuContext ctx) => Unset(ctx, 41, 82);
    // V44_EXPORT_END nid=HRBeLG106ww

    // V44_EXPORT_BEGIN nid=6l451ru3SJg
    [SysAbiExport(
        Nid = "6l451ru3SJg",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreateD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2022(CpuContext ctx) => Destruct(ctx, 41);
    // V44_EXPORT_END nid=6l451ru3SJg

    // V44_EXPORT_BEGIN nid=No7x9VUQX28
    [SysAbiExport(
        Nid = "No7x9VUQX28",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V121PlayerForTicketCreateD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2023(CpuContext ctx) => Destruct(ctx, 41);
    // V44_EXPORT_END nid=No7x9VUQX28

    // V44_EXPORT_BEGIN nid=+NXjg-1KWPc
    [SysAbiExport(
        Nid = "+NXjg-1KWPc",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V19SubmitterC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2094(CpuContext ctx) => Construct(ctx, 42);
    // V44_EXPORT_END nid=+NXjg-1KWPc

    // V44_EXPORT_BEGIN nid=W7EnziA8B5Y
    [SysAbiExport(
        Nid = "W7EnziA8B5Y",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V19SubmitterC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2095(CpuContext ctx) => Construct(ctx, 42);
    // V44_EXPORT_END nid=W7EnziA8B5Y

    // V44_EXPORT_BEGIN nid=ZL5Azk2U+XI
    [SysAbiExport(
        Nid = "ZL5Azk2U+XI",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V19Submitter14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2096(CpuContext ctx) => IsSet(ctx, 42, 83);
    // V44_EXPORT_END nid=ZL5Azk2U+XI

    // V44_EXPORT_BEGIN nid=KJLvDqmFiKk
    [SysAbiExport(
        Nid = "KJLvDqmFiKk",
        ExportName = "_ZNK3sce2Np9CppWebApi11Matchmaking2V19Submitter12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2098(CpuContext ctx) => GetValue(ctx, 42, 83, ReturnKind.U64);
    // V44_EXPORT_END nid=KJLvDqmFiKk

    // V44_EXPORT_BEGIN nid=9HGfqQKOYPk
    [SysAbiExport(
        Nid = "9HGfqQKOYPk",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V19Submitter12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2101(CpuContext ctx) => SetValue(ctx, 42, 83, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=9HGfqQKOYPk

    // V44_EXPORT_BEGIN nid=LdAhxF8siFI
    [SysAbiExport(
        Nid = "LdAhxF8siFI",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V19Submitter14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2104(CpuContext ctx) => Unset(ctx, 42, 83);
    // V44_EXPORT_END nid=LdAhxF8siFI

    // V44_EXPORT_BEGIN nid=91tmX-hOiP4
    [SysAbiExport(
        Nid = "91tmX-hOiP4",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V19SubmitterD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2106(CpuContext ctx) => Destruct(ctx, 42);
    // V44_EXPORT_END nid=91tmX-hOiP4

    // V44_EXPORT_BEGIN nid=ltDpo4Q53sY
    [SysAbiExport(
        Nid = "ltDpo4Q53sY",
        ExportName = "_ZN3sce2Np9CppWebApi11Matchmaking2V19SubmitterD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2107(CpuContext ctx) => Destruct(ctx, 42);
    // V44_EXPORT_END nid=ltDpo4Q53sY

    // V44_EXPORT_BEGIN nid=fw+Z69DzrpQ
    [SysAbiExport(
        Nid = "fw+Z69DzrpQ",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V15ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2155(CpuContext ctx) => Construct(ctx, 43);
    // V44_EXPORT_END nid=fw+Z69DzrpQ

    // V44_EXPORT_BEGIN nid=l+Ug1Xfqhxw
    [SysAbiExport(
        Nid = "l+Ug1Xfqhxw",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V15ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2156(CpuContext ctx) => Construct(ctx, 43);
    // V44_EXPORT_END nid=l+Ug1Xfqhxw

    // V44_EXPORT_BEGIN nid=YkTPIi0jZ6E
    [SysAbiExport(
        Nid = "YkTPIi0jZ6E",
        ExportName = "_ZNK3sce2Np9CppWebApi15Personalization2V15Error9codeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2157(CpuContext ctx) => IsSet(ctx, 43, 84);
    // V44_EXPORT_END nid=YkTPIi0jZ6E

    // V44_EXPORT_BEGIN nid=TmnhYAJKyHk
    [SysAbiExport(
        Nid = "TmnhYAJKyHk",
        ExportName = "_ZNK3sce2Np9CppWebApi15Personalization2V15Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2159(CpuContext ctx) => GetValue(ctx, 43, 84, ReturnKind.U32);
    // V44_EXPORT_END nid=TmnhYAJKyHk

    // V44_EXPORT_BEGIN nid=f6UEsqGDGYg
    [SysAbiExport(
        Nid = "f6UEsqGDGYg",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V15Error7setCodeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2167(CpuContext ctx) => SetValue(ctx, 43, 84, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=f6UEsqGDGYg

    // V44_EXPORT_BEGIN nid=2ioZrakRg1M
    [SysAbiExport(
        Nid = "2ioZrakRg1M",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V15Error9unsetCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2174(CpuContext ctx) => Unset(ctx, 43, 84);
    // V44_EXPORT_END nid=2ioZrakRg1M

    // V44_EXPORT_BEGIN nid=1ELEdwIoIwU
    [SysAbiExport(
        Nid = "1ELEdwIoIwU",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V15ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2179(CpuContext ctx) => Destruct(ctx, 43);
    // V44_EXPORT_END nid=1ELEdwIoIwU

    // V44_EXPORT_BEGIN nid=OKuCgQvFoW0
    [SysAbiExport(
        Nid = "OKuCgQvFoW0",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V15ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2180(CpuContext ctx) => Destruct(ctx, 43);
    // V44_EXPORT_END nid=OKuCgQvFoW0

    // V44_EXPORT_BEGIN nid=3CNVYZj-sfE
    [SysAbiExport(
        Nid = "3CNVYZj-sfE",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V121GetAccessCodeResponseC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2197(CpuContext ctx) => Construct(ctx, 44);
    // V44_EXPORT_END nid=3CNVYZj-sfE

    // V44_EXPORT_BEGIN nid=jFLOYtUyrko
    [SysAbiExport(
        Nid = "jFLOYtUyrko",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V121GetAccessCodeResponseC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2198(CpuContext ctx) => Construct(ctx, 44);
    // V44_EXPORT_END nid=jFLOYtUyrko

    // V44_EXPORT_BEGIN nid=K+yeXWdjPa8
    [SysAbiExport(
        Nid = "K+yeXWdjPa8",
        ExportName = "_ZNK3sce2Np9CppWebApi15Personalization2V121GetAccessCodeResponse12getExpiresAtEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2201(CpuContext ctx) => GetValue(ctx, 44, 85, ReturnKind.U64);
    // V44_EXPORT_END nid=K+yeXWdjPa8

    // V44_EXPORT_BEGIN nid=SnsJfGiP3Bg
    [SysAbiExport(
        Nid = "SnsJfGiP3Bg",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V121GetAccessCodeResponse12setExpiresAtERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2204(CpuContext ctx) => SetValue(ctx, 44, 85, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=SnsJfGiP3Bg

    // V44_EXPORT_BEGIN nid=2K2ZFsGumc8
    [SysAbiExport(
        Nid = "2K2ZFsGumc8",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V121GetAccessCodeResponseD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2207(CpuContext ctx) => Destruct(ctx, 44);
    // V44_EXPORT_END nid=2K2ZFsGumc8

    // V44_EXPORT_BEGIN nid=U1dyXoMJpOU
    [SysAbiExport(
        Nid = "U1dyXoMJpOU",
        ExportName = "_ZN3sce2Np9CppWebApi15Personalization2V121GetAccessCodeResponseD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2208(CpuContext ctx) => Destruct(ctx, 44);
    // V44_EXPORT_END nid=U1dyXoMJpOU

    // V44_EXPORT_BEGIN nid=N0ACqxdL4w8
    [SysAbiExport(
        Nid = "N0ACqxdL4w8",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_errorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2296(CpuContext ctx) => Construct(ctx, 45);
    // V44_EXPORT_END nid=N0ACqxdL4w8

    // V44_EXPORT_BEGIN nid=T4S6GbHkXUI
    [SysAbiExport(
        Nid = "T4S6GbHkXUI",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_errorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2297(CpuContext ctx) => Construct(ctx, 45);
    // V44_EXPORT_END nid=T4S6GbHkXUI

    // V44_EXPORT_BEGIN nid=uqHkyjI7MOk
    [SysAbiExport(
        Nid = "uqHkyjI7MOk",
        ExportName = "_ZNK3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error9codeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2298(CpuContext ctx) => IsSet(ctx, 45, 86);
    // V44_EXPORT_END nid=uqHkyjI7MOk

    // V44_EXPORT_BEGIN nid=SyaPNlB3Lvg
    [SysAbiExport(
        Nid = "SyaPNlB3Lvg",
        ExportName = "_ZNK3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2300(CpuContext ctx) => GetValue(ctx, 45, 86, ReturnKind.U32);
    // V44_EXPORT_END nid=SyaPNlB3Lvg

    // V44_EXPORT_BEGIN nid=L1ifnzzsPQ4
    [SysAbiExport(
        Nid = "L1ifnzzsPQ4",
        ExportName = "_ZNK3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error9getStatusEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2302(CpuContext ctx) => GetValue(ctx, 45, 87, ReturnKind.U32);
    // V44_EXPORT_END nid=L1ifnzzsPQ4

    // V44_EXPORT_BEGIN nid=ozTHRE6r2iI
    [SysAbiExport(
        Nid = "ozTHRE6r2iI",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error7setCodeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2305(CpuContext ctx) => SetValue(ctx, 45, 86, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=ozTHRE6r2iI

    // V44_EXPORT_BEGIN nid=36YjmziKXoc
    [SysAbiExport(
        Nid = "36YjmziKXoc",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error9setStatusERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2307(CpuContext ctx) => SetValue(ctx, 45, 87, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=36YjmziKXoc

    // V44_EXPORT_BEGIN nid=SYoL1PVQ7bY
    [SysAbiExport(
        Nid = "SYoL1PVQ7bY",
        ExportName = "_ZNK3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error11statusIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2309(CpuContext ctx) => IsSet(ctx, 45, 87);
    // V44_EXPORT_END nid=SYoL1PVQ7bY

    // V44_EXPORT_BEGIN nid=CluPe2pSlWw
    [SysAbiExport(
        Nid = "CluPe2pSlWw",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error9unsetCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2312(CpuContext ctx) => Unset(ctx, 45, 86);
    // V44_EXPORT_END nid=CluPe2pSlWw

    // V44_EXPORT_BEGIN nid=9L5spctC4FQ
    [SysAbiExport(
        Nid = "9L5spctC4FQ",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_error11unsetStatusEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2314(CpuContext ctx) => Unset(ctx, 45, 87);
    // V44_EXPORT_END nid=9L5spctC4FQ

    // V44_EXPORT_BEGIN nid=SMuOUDRFSw0
    [SysAbiExport(
        Nid = "SMuOUDRFSw0",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_errorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2316(CpuContext ctx) => Destruct(ctx, 45);
    // V44_EXPORT_END nid=SMuOUDRFSw0

    // V44_EXPORT_BEGIN nid=t2oH2VXgmqY
    [SysAbiExport(
        Nid = "t2oH2VXgmqY",
        ExportName = "_ZN3sce2Np9CppWebApi15ProfanityFilter2V225WebApiErrorResponse_errorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2317(CpuContext ctx) => Destruct(ctx, 45);
    // V44_EXPORT_END nid=t2oH2VXgmqY

    // V44_EXPORT_BEGIN nid=GAIvEDR+FEs
    [SysAbiExport(
        Nid = "GAIvEDR+FEs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V15ErrorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2332(CpuContext ctx) => Construct(ctx, 46);
    // V44_EXPORT_END nid=GAIvEDR+FEs

    // V44_EXPORT_BEGIN nid=PcgRdxUZ03o
    [SysAbiExport(
        Nid = "PcgRdxUZ03o",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V15ErrorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2333(CpuContext ctx) => Construct(ctx, 46);
    // V44_EXPORT_END nid=PcgRdxUZ03o

    // V44_EXPORT_BEGIN nid=aP7Vf01mqKo
    [SysAbiExport(
        Nid = "aP7Vf01mqKo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V15Error7getCodeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2335(CpuContext ctx) => GetValue(ctx, 46, 88, ReturnKind.U64);
    // V44_EXPORT_END nid=aP7Vf01mqKo

    // V44_EXPORT_BEGIN nid=65U47xQLX-I
    [SysAbiExport(
        Nid = "65U47xQLX-I",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V15Error7setCodeERKl",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2342(CpuContext ctx) => SetValue(ctx, 46, 88, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=65U47xQLX-I

    // V44_EXPORT_BEGIN nid=7hb4tWFbBqI
    [SysAbiExport(
        Nid = "7hb4tWFbBqI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V15ErrorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2352(CpuContext ctx) => Destruct(ctx, 46);
    // V44_EXPORT_END nid=7hb4tWFbBqI

    // V44_EXPORT_BEGIN nid=jXYtyfAp-n4
    [SysAbiExport(
        Nid = "jXYtyfAp-n4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V15ErrorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2353(CpuContext ctx) => Destruct(ctx, 46);
    // V44_EXPORT_END nid=jXYtyfAp-n4

    // V44_EXPORT_BEGIN nid=8xgKWJVwQMI
    [SysAbiExport(
        Nid = "8xgKWJVwQMI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V16FriendC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2368(CpuContext ctx) => Construct(ctx, 47);
    // V44_EXPORT_END nid=8xgKWJVwQMI

    // V44_EXPORT_BEGIN nid=ASCvvxlvfMc
    [SysAbiExport(
        Nid = "ASCvvxlvfMc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V16FriendC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2369(CpuContext ctx) => Construct(ctx, 47);
    // V44_EXPORT_END nid=ASCvvxlvfMc

    // V44_EXPORT_BEGIN nid=4z03CDKv6IA
    [SysAbiExport(
        Nid = "4z03CDKv6IA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V16Friend14accountIdIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2370(CpuContext ctx) => IsSet(ctx, 47, 89);
    // V44_EXPORT_END nid=4z03CDKv6IA

    // V44_EXPORT_BEGIN nid=J6eF2N6k0EQ
    [SysAbiExport(
        Nid = "J6eF2N6k0EQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V16Friend12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2372(CpuContext ctx) => GetValue(ctx, 47, 89, ReturnKind.U64);
    // V44_EXPORT_END nid=J6eF2N6k0EQ

    // V44_EXPORT_BEGIN nid=NOmLjKNQLdQ
    [SysAbiExport(
        Nid = "NOmLjKNQLdQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V16Friend12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2377(CpuContext ctx) => SetValue(ctx, 47, 89, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=NOmLjKNQLdQ

    // V44_EXPORT_BEGIN nid=K2pwXRnawg0
    [SysAbiExport(
        Nid = "K2pwXRnawg0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V16Friend14unsetAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2381(CpuContext ctx) => Unset(ctx, 47, 89);
    // V44_EXPORT_END nid=K2pwXRnawg0

    // V44_EXPORT_BEGIN nid=2fe0xrpkq0s
    [SysAbiExport(
        Nid = "2fe0xrpkq0s",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V16FriendD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2384(CpuContext ctx) => Destruct(ctx, 47);
    // V44_EXPORT_END nid=2fe0xrpkq0s

    // V44_EXPORT_BEGIN nid=VUOgrSpFbh8
    [SysAbiExport(
        Nid = "VUOgrSpFbh8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V16FriendD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2385(CpuContext ctx) => Destruct(ctx, 47);
    // V44_EXPORT_END nid=VUOgrSpFbh8

    // V44_EXPORT_BEGIN nid=6MBAIH50vB4
    [SysAbiExport(
        Nid = "6MBAIH50vB4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V110FromMemberC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2418(CpuContext ctx) => Construct(ctx, 48);
    // V44_EXPORT_END nid=6MBAIH50vB4

    // V44_EXPORT_BEGIN nid=fzp8a-tnBGw
    [SysAbiExport(
        Nid = "fzp8a-tnBGw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V110FromMemberC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2419(CpuContext ctx) => Construct(ctx, 48);
    // V44_EXPORT_END nid=fzp8a-tnBGw

    // V44_EXPORT_BEGIN nid=1nafvh3INrY
    [SysAbiExport(
        Nid = "1nafvh3INrY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V110FromMember12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2421(CpuContext ctx) => GetValue(ctx, 48, 90, ReturnKind.U64);
    // V44_EXPORT_END nid=1nafvh3INrY

    // V44_EXPORT_BEGIN nid=HVTfSNXNkDM
    [SysAbiExport(
        Nid = "HVTfSNXNkDM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V110FromMember12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2424(CpuContext ctx) => SetValue(ctx, 48, 90, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=HVTfSNXNkDM

    // V44_EXPORT_BEGIN nid=dc7NozegWtA
    [SysAbiExport(
        Nid = "dc7NozegWtA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V110FromMemberD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2428(CpuContext ctx) => Destruct(ctx, 48);
    // V44_EXPORT_END nid=dc7NozegWtA

    // V44_EXPORT_BEGIN nid=tpLPh+8xIiQ
    [SysAbiExport(
        Nid = "tpLPh+8xIiQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V110FromMemberD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2429(CpuContext ctx) => Destruct(ctx, 48);
    // V44_EXPORT_END nid=tpLPh+8xIiQ

    // V44_EXPORT_BEGIN nid=8Jrc5Nub3mY
    [SysAbiExport(
        Nid = "8Jrc5Nub3mY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForReadC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2459(CpuContext ctx) => Construct(ctx, 49);
    // V44_EXPORT_END nid=8Jrc5Nub3mY

    // V44_EXPORT_BEGIN nid=o3Vk4PDllJc
    [SysAbiExport(
        Nid = "o3Vk4PDllJc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForReadC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2460(CpuContext ctx) => Construct(ctx, 49);
    // V44_EXPORT_END nid=o3Vk4PDllJc

    // V44_EXPORT_BEGIN nid=k2IDcx-apvQ
    [SysAbiExport(
        Nid = "k2IDcx-apvQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead15getJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2468(CpuContext ctx) => GetValue(ctx, 49, 91, ReturnKind.Bool);
    // V44_EXPORT_END nid=k2IDcx-apvQ

    // V44_EXPORT_BEGIN nid=y0BDcAt6FGE
    [SysAbiExport(
        Nid = "y0BDcAt6FGE",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead13getMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2470(CpuContext ctx) => GetValue(ctx, 49, 92, ReturnKind.U32);
    // V44_EXPORT_END nid=y0BDcAt6FGE

    // V44_EXPORT_BEGIN nid=aezUahhkO0A
    [SysAbiExport(
        Nid = "aezUahhkO0A",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead16getMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2471(CpuContext ctx) => GetValue(ctx, 49, 93, ReturnKind.U32);
    // V44_EXPORT_END nid=aezUahhkO0A

    // V44_EXPORT_BEGIN nid=1WCDRJQQWwM
    [SysAbiExport(
        Nid = "1WCDRJQQWwM",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead28getReservationTimeoutSecondsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2474(CpuContext ctx) => GetValue(ctx, 49, 94, ReturnKind.U32);
    // V44_EXPORT_END nid=1WCDRJQQWwM

    // V44_EXPORT_BEGIN nid=lAFKNV82Fds
    [SysAbiExport(
        Nid = "lAFKNV82Fds",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead13getSearchableEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2477(CpuContext ctx) => GetValue(ctx, 49, 95, ReturnKind.Bool);
    // V44_EXPORT_END nid=lAFKNV82Fds

    // V44_EXPORT_BEGIN nid=AtvOgVdBLNA
    [SysAbiExport(
        Nid = "AtvOgVdBLNA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead19getUsePlayerSessionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2480(CpuContext ctx) => GetValue(ctx, 49, 96, ReturnKind.Bool);
    // V44_EXPORT_END nid=AtvOgVdBLNA

    // V44_EXPORT_BEGIN nid=SBIme60FhnY
    [SysAbiExport(
        Nid = "SBIme60FhnY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead17joinDisabledIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2481(CpuContext ctx) => IsSet(ctx, 49, 91);
    // V44_EXPORT_END nid=SBIme60FhnY

    // V44_EXPORT_BEGIN nid=LO70m1BiJPM
    [SysAbiExport(
        Nid = "LO70m1BiJPM",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead15maxPlayersIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2483(CpuContext ctx) => IsSet(ctx, 49, 92);
    // V44_EXPORT_END nid=LO70m1BiJPM

    // V44_EXPORT_BEGIN nid=DE2yor5gKVY
    [SysAbiExport(
        Nid = "DE2yor5gKVY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead18maxSpectatorsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2484(CpuContext ctx) => IsSet(ctx, 49, 93);
    // V44_EXPORT_END nid=DE2yor5gKVY

    // V44_EXPORT_BEGIN nid=dgLPhYb+SDc
    [SysAbiExport(
        Nid = "dgLPhYb+SDc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead30reservationTimeoutSecondsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2487(CpuContext ctx) => IsSet(ctx, 49, 94);
    // V44_EXPORT_END nid=dgLPhYb+SDc

    // V44_EXPORT_BEGIN nid=RpyEppnI3OI
    [SysAbiExport(
        Nid = "RpyEppnI3OI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead15searchableIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2490(CpuContext ctx) => IsSet(ctx, 49, 95);
    // V44_EXPORT_END nid=RpyEppnI3OI

    // V44_EXPORT_BEGIN nid=IsVVlFOqJ7w
    [SysAbiExport(
        Nid = "IsVVlFOqJ7w",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead15setJoinDisabledERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2495(CpuContext ctx) => SetValue(ctx, 49, 91, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=IsVVlFOqJ7w

    // V44_EXPORT_BEGIN nid=LOXtzVeGnDg
    [SysAbiExport(
        Nid = "LOXtzVeGnDg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead13setMaxPlayersERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2497(CpuContext ctx) => SetValue(ctx, 49, 92, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=LOXtzVeGnDg

    // V44_EXPORT_BEGIN nid=frkxOcdxRY0
    [SysAbiExport(
        Nid = "frkxOcdxRY0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead16setMaxSpectatorsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2498(CpuContext ctx) => SetValue(ctx, 49, 93, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=frkxOcdxRY0

    // V44_EXPORT_BEGIN nid=mQPLN+TiRDo
    [SysAbiExport(
        Nid = "mQPLN+TiRDo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead28setReservationTimeoutSecondsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2501(CpuContext ctx) => SetValue(ctx, 49, 94, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=mQPLN+TiRDo

    // V44_EXPORT_BEGIN nid=Ug-xd4ry1hg
    [SysAbiExport(
        Nid = "Ug-xd4ry1hg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead13setSearchableERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2504(CpuContext ctx) => SetValue(ctx, 49, 95, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=Ug-xd4ry1hg

    // V44_EXPORT_BEGIN nid=oov4LEYfr4o
    [SysAbiExport(
        Nid = "oov4LEYfr4o",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead19setUsePlayerSessionERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2507(CpuContext ctx) => SetValue(ctx, 49, 96, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=oov4LEYfr4o

    // V44_EXPORT_BEGIN nid=tTBDMlVQIo0
    [SysAbiExport(
        Nid = "tTBDMlVQIo0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead17unsetJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2513(CpuContext ctx) => Unset(ctx, 49, 91);
    // V44_EXPORT_END nid=tTBDMlVQIo0

    // V44_EXPORT_BEGIN nid=iCoS6S-NtEw
    [SysAbiExport(
        Nid = "iCoS6S-NtEw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead15unsetMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2515(CpuContext ctx) => Unset(ctx, 49, 92);
    // V44_EXPORT_END nid=iCoS6S-NtEw

    // V44_EXPORT_BEGIN nid=qQoLWGXNlDI
    [SysAbiExport(
        Nid = "qQoLWGXNlDI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead18unsetMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2516(CpuContext ctx) => Unset(ctx, 49, 93);
    // V44_EXPORT_END nid=qQoLWGXNlDI

    // V44_EXPORT_BEGIN nid=Ok35SiBrHA4
    [SysAbiExport(
        Nid = "Ok35SiBrHA4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead30unsetReservationTimeoutSecondsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2519(CpuContext ctx) => Unset(ctx, 49, 94);
    // V44_EXPORT_END nid=Ok35SiBrHA4

    // V44_EXPORT_BEGIN nid=LQDkC+LFW+0
    [SysAbiExport(
        Nid = "LQDkC+LFW+0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead15unsetSearchableEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2522(CpuContext ctx) => Unset(ctx, 49, 95);
    // V44_EXPORT_END nid=LQDkC+LFW+0

    // V44_EXPORT_BEGIN nid=a2xNcwL7WaI
    [SysAbiExport(
        Nid = "a2xNcwL7WaI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead21unsetUsePlayerSessionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2525(CpuContext ctx) => Unset(ctx, 49, 96);
    // V44_EXPORT_END nid=a2xNcwL7WaI

    // V44_EXPORT_BEGIN nid=zS-rkk0AOoY
    [SysAbiExport(
        Nid = "zS-rkk0AOoY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118GameSessionForRead21usePlayerSessionIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2526(CpuContext ctx) => IsSet(ctx, 49, 96);
    // V44_EXPORT_END nid=zS-rkk0AOoY

    // V44_EXPORT_BEGIN nid=Xw6MRw0otvY
    [SysAbiExport(
        Nid = "Xw6MRw0otvY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForReadD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2527(CpuContext ctx) => Destruct(ctx, 49);
    // V44_EXPORT_END nid=Xw6MRw0otvY

    // V44_EXPORT_BEGIN nid=xiauk1N3Esw
    [SysAbiExport(
        Nid = "xiauk1N3Esw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118GameSessionForReadD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2528(CpuContext ctx) => Destruct(ctx, 49);
    // V44_EXPORT_END nid=xiauk1N3Esw

    // V44_EXPORT_BEGIN nid=-CyKFkZr9Yg
    [SysAbiExport(
        Nid = "-CyKFkZr9Yg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2549(CpuContext ctx) => Construct(ctx, 50);
    // V44_EXPORT_END nid=-CyKFkZr9Yg

    // V44_EXPORT_BEGIN nid=JQqAOeX3ai8
    [SysAbiExport(
        Nid = "JQqAOeX3ai8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2550(CpuContext ctx) => Construct(ctx, 50);
    // V44_EXPORT_END nid=JQqAOeX3ai8

    // V44_EXPORT_BEGIN nid=4ephroQdYfA
    [SysAbiExport(
        Nid = "4ephroQdYfA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayer12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2553(CpuContext ctx) => GetValue(ctx, 50, 97, ReturnKind.U64);
    // V44_EXPORT_END nid=4ephroQdYfA

    // V44_EXPORT_BEGIN nid=3o0x1RR++Ng
    [SysAbiExport(
        Nid = "3o0x1RR++Ng",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayer10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2557(CpuContext ctx) => GetValue(ctx, 50, 98, ReturnKind.U32);
    // V44_EXPORT_END nid=3o0x1RR++Ng

    // V44_EXPORT_BEGIN nid=xJRyp4B6KSI
    [SysAbiExport(
        Nid = "xJRyp4B6KSI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayer12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2561(CpuContext ctx) => IsSet(ctx, 50, 98);
    // V44_EXPORT_END nid=xJRyp4B6KSI

    // V44_EXPORT_BEGIN nid=6eWqhVnss2E
    [SysAbiExport(
        Nid = "6eWqhVnss2E",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayer12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2562(CpuContext ctx) => SetValue(ctx, 50, 97, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=6eWqhVnss2E

    // V44_EXPORT_BEGIN nid=udhcXivSwFQ
    [SysAbiExport(
        Nid = "udhcXivSwFQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayer10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2566(CpuContext ctx) => SetValue(ctx, 50, 98, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=udhcXivSwFQ

    // V44_EXPORT_BEGIN nid=Midd3txC-9g
    [SysAbiExport(
        Nid = "Midd3txC-9g",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayer12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2572(CpuContext ctx) => Unset(ctx, 50, 98);
    // V44_EXPORT_END nid=Midd3txC-9g

    // V44_EXPORT_BEGIN nid=2zFFtiMV6D8
    [SysAbiExport(
        Nid = "2zFFtiMV6D8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2573(CpuContext ctx) => Destruct(ctx, 50);
    // V44_EXPORT_END nid=2zFFtiMV6D8

    // V44_EXPORT_BEGIN nid=v7RJfl5wa6M
    [SysAbiExport(
        Nid = "v7RJfl5wa6M",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V117GameSessionPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2574(CpuContext ctx) => Destruct(ctx, 50);
    // V44_EXPORT_END nid=v7RJfl5wa6M

    // V44_EXPORT_BEGIN nid=QsMOCBGAXkw
    [SysAbiExport(
        Nid = "QsMOCBGAXkw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectatorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2589(CpuContext ctx) => Construct(ctx, 51);
    // V44_EXPORT_END nid=QsMOCBGAXkw

    // V44_EXPORT_BEGIN nid=bAho0zsG+C0
    [SysAbiExport(
        Nid = "bAho0zsG+C0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectatorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2590(CpuContext ctx) => Construct(ctx, 51);
    // V44_EXPORT_END nid=bAho0zsG+C0

    // V44_EXPORT_BEGIN nid=GoMPhCyp74o
    [SysAbiExport(
        Nid = "GoMPhCyp74o",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectator12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2593(CpuContext ctx) => GetValue(ctx, 51, 99, ReturnKind.U64);
    // V44_EXPORT_END nid=GoMPhCyp74o

    // V44_EXPORT_BEGIN nid=CvpEQIpe-Ng
    [SysAbiExport(
        Nid = "CvpEQIpe-Ng",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectator10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2597(CpuContext ctx) => GetValue(ctx, 51, 100, ReturnKind.U32);
    // V44_EXPORT_END nid=CvpEQIpe-Ng

    // V44_EXPORT_BEGIN nid=4UlyNf+YwYU
    [SysAbiExport(
        Nid = "4UlyNf+YwYU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectator12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2601(CpuContext ctx) => IsSet(ctx, 51, 100);
    // V44_EXPORT_END nid=4UlyNf+YwYU

    // V44_EXPORT_BEGIN nid=KjW6KDcAnuA
    [SysAbiExport(
        Nid = "KjW6KDcAnuA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectator12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2602(CpuContext ctx) => SetValue(ctx, 51, 99, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=KjW6KDcAnuA

    // V44_EXPORT_BEGIN nid=Eh4A9qNAKvM
    [SysAbiExport(
        Nid = "Eh4A9qNAKvM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectator10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2606(CpuContext ctx) => SetValue(ctx, 51, 100, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=Eh4A9qNAKvM

    // V44_EXPORT_BEGIN nid=QlBsNs+u6MU
    [SysAbiExport(
        Nid = "QlBsNs+u6MU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectator12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2612(CpuContext ctx) => Unset(ctx, 51, 100);
    // V44_EXPORT_END nid=QlBsNs+u6MU

    // V44_EXPORT_BEGIN nid=4roTaiqqXQE
    [SysAbiExport(
        Nid = "4roTaiqqXQE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectatorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2613(CpuContext ctx) => Destruct(ctx, 51);
    // V44_EXPORT_END nid=4roTaiqqXQE

    // V44_EXPORT_BEGIN nid=h9Ak0tSAc0A
    [SysAbiExport(
        Nid = "h9Ak0tSAc0A",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120GameSessionSpectatorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2614(CpuContext ctx) => Destruct(ctx, 51);
    // V44_EXPORT_END nid=h9Ak0tSAc0A

    // V44_EXPORT_BEGIN nid=eDNxhgdz6zE
    [SysAbiExport(
        Nid = "eDNxhgdz6zE",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V115GameSessionsApi33ParameterToPostGameSessionsSearch8getlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2790(CpuContext ctx) => GetValue(ctx, 52, 101, ReturnKind.U32);
    // V44_EXPORT_END nid=eDNxhgdz6zE

    // V44_EXPORT_BEGIN nid=zsOqjXApJOQ
    [SysAbiExport(
        Nid = "zsOqjXApJOQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V115GameSessionsApi33ParameterToPostGameSessionsSearch8haslimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2793(CpuContext ctx) => IsSet(ctx, 52, 101);
    // V44_EXPORT_END nid=zsOqjXApJOQ

    // V44_EXPORT_BEGIN nid=eu0j+42u4XI
    [SysAbiExport(
        Nid = "eu0j+42u4XI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115GameSessionsApi33ParameterToPostGameSessionsSearch8setlimitEi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2797(CpuContext ctx) => SetValue(ctx, 52, 101, ValueSource.Register, false);
    // V44_EXPORT_END nid=eu0j+42u4XI

    // V44_EXPORT_BEGIN nid=7Jnbrbv+QNA
    [SysAbiExport(
        Nid = "7Jnbrbv+QNA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115GameSessionsApi33ParameterToPostGameSessionsSearch10unsetlimitEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2801(CpuContext ctx) => Unset(ctx, 52, 101);
    // V44_EXPORT_END nid=7Jnbrbv+QNA

    // V44_EXPORT_BEGIN nid=Ww+JDt-JBn8
    [SysAbiExport(
        Nid = "Ww+JDt-JBn8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115GameSessionsApi33ParameterToPostGameSessionsSearchD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2802(CpuContext ctx) => Destruct(ctx, 52);
    // V44_EXPORT_END nid=Ww+JDt-JBn8

    // V44_EXPORT_BEGIN nid=fRBNJ0emf8s
    [SysAbiExport(
        Nid = "fRBNJ0emf8s",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V115GameSessionsApi33ParameterToPostGameSessionsSearchD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2803(CpuContext ctx) => Destruct(ctx, 52);
    // V44_EXPORT_END nid=fRBNJ0emf8s

    // V44_EXPORT_BEGIN nid=2e82MxFnonI
    [SysAbiExport(
        Nid = "2e82MxFnonI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V112JoinableUserC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2962(CpuContext ctx) => Construct(ctx, 53);
    // V44_EXPORT_END nid=2e82MxFnonI

    // V44_EXPORT_BEGIN nid=qorBNOn3BWk
    [SysAbiExport(
        Nid = "qorBNOn3BWk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V112JoinableUserC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2963(CpuContext ctx) => Construct(ctx, 53);
    // V44_EXPORT_END nid=qorBNOn3BWk

    // V44_EXPORT_BEGIN nid=R0KW845D-BE
    [SysAbiExport(
        Nid = "R0KW845D-BE",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V112JoinableUser12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2965(CpuContext ctx) => GetValue(ctx, 53, 102, ReturnKind.U64);
    // V44_EXPORT_END nid=R0KW845D-BE

    // V44_EXPORT_BEGIN nid=PfoqqnKHFho
    [SysAbiExport(
        Nid = "PfoqqnKHFho",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V112JoinableUser12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2966(CpuContext ctx) => SetValue(ctx, 53, 102, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=PfoqqnKHFho

    // V44_EXPORT_BEGIN nid=FOkC5Gjb72A
    [SysAbiExport(
        Nid = "FOkC5Gjb72A",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V112JoinableUserD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2968(CpuContext ctx) => Destruct(ctx, 53);
    // V44_EXPORT_END nid=FOkC5Gjb72A

    // V44_EXPORT_BEGIN nid=Y7QXcOWtIB4
    [SysAbiExport(
        Nid = "Y7QXcOWtIB4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V112JoinableUserD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2969(CpuContext ctx) => Destruct(ctx, 53);
    // V44_EXPORT_END nid=Y7QXcOWtIB4

    // V44_EXPORT_BEGIN nid=VnngGyk0Wew
    [SysAbiExport(
        Nid = "VnngGyk0Wew",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatformC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2973(CpuContext ctx) => Construct(ctx, 54);
    // V44_EXPORT_END nid=VnngGyk0Wew

    // V44_EXPORT_BEGIN nid=n-hVvL9XmlM
    [SysAbiExport(
        Nid = "n-hVvL9XmlM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatformC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2974(CpuContext ctx) => Construct(ctx, 54);
    // V44_EXPORT_END nid=n-hVvL9XmlM

    // V44_EXPORT_BEGIN nid=6TxzHeN5tro
    [SysAbiExport(
        Nid = "6TxzHeN5tro",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatform19getUsePlayerSessionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2979(CpuContext ctx) => GetValue(ctx, 54, 103, ReturnKind.Bool);
    // V44_EXPORT_END nid=6TxzHeN5tro

    // V44_EXPORT_BEGIN nid=LfPJj2RfuWU
    [SysAbiExport(
        Nid = "LfPJj2RfuWU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatform19setUsePlayerSessionERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2986(CpuContext ctx) => SetValue(ctx, 54, 103, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=LfPJj2RfuWU

    // V44_EXPORT_BEGIN nid=E8UvmmmIIzQ
    [SysAbiExport(
        Nid = "E8UvmmmIIzQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatform21unsetUsePlayerSessionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2991(CpuContext ctx) => Unset(ctx, 54, 103);
    // V44_EXPORT_END nid=E8UvmmmIIzQ

    // V44_EXPORT_BEGIN nid=Tdeqyz8zWnw
    [SysAbiExport(
        Nid = "Tdeqyz8zWnw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatform21usePlayerSessionIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2992(CpuContext ctx) => IsSet(ctx, 54, 103);
    // V44_EXPORT_END nid=Tdeqyz8zWnw

    // V44_EXPORT_BEGIN nid=Vv6rsGkhZzU
    [SysAbiExport(
        Nid = "Vv6rsGkhZzU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatformD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2993(CpuContext ctx) => Destruct(ctx, 54);
    // V44_EXPORT_END nid=Vv6rsGkhZzU

    // V44_EXPORT_BEGIN nid=r8knxrn-LZ8
    [SysAbiExport(
        Nid = "r8knxrn-LZ8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V129JoinedGameSessionWithPlatformD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api2994(CpuContext ctx) => Destruct(ctx, 54);
    // V44_EXPORT_END nid=r8knxrn-LZ8

    // V44_EXPORT_BEGIN nid=Y35OA3dFPhk
    [SysAbiExport(
        Nid = "Y35OA3dFPhk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118LeaderWithOnlineIdC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3015(CpuContext ctx) => Construct(ctx, 55);
    // V44_EXPORT_END nid=Y35OA3dFPhk

    // V44_EXPORT_BEGIN nid=oZ5khLR19g4
    [SysAbiExport(
        Nid = "oZ5khLR19g4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118LeaderWithOnlineIdC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3016(CpuContext ctx) => Construct(ctx, 55);
    // V44_EXPORT_END nid=oZ5khLR19g4

    // V44_EXPORT_BEGIN nid=sW6h+-un80k
    [SysAbiExport(
        Nid = "sW6h+-un80k",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118LeaderWithOnlineId12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3018(CpuContext ctx) => GetValue(ctx, 55, 104, ReturnKind.U64);
    // V44_EXPORT_END nid=sW6h+-un80k

    // V44_EXPORT_BEGIN nid=6b-RkK-dpw0
    [SysAbiExport(
        Nid = "6b-RkK-dpw0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118LeaderWithOnlineId12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3021(CpuContext ctx) => SetValue(ctx, 55, 104, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=6b-RkK-dpw0

    // V44_EXPORT_BEGIN nid=RvnbP6R6-Oc
    [SysAbiExport(
        Nid = "RvnbP6R6-Oc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118LeaderWithOnlineIdD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3025(CpuContext ctx) => Destruct(ctx, 55);
    // V44_EXPORT_END nid=RvnbP6R6-Oc

    // V44_EXPORT_BEGIN nid=fi11ETDjPOw
    [SysAbiExport(
        Nid = "fi11ETDjPOw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118LeaderWithOnlineIdD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3026(CpuContext ctx) => Destruct(ctx, 55);
    // V44_EXPORT_END nid=fi11ETDjPOw

    // V44_EXPORT_BEGIN nid=41AsKYHp-QM
    [SysAbiExport(
        Nid = "41AsKYHp-QM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V123MemberWithMultiPlatformC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3054(CpuContext ctx) => Construct(ctx, 56);
    // V44_EXPORT_END nid=41AsKYHp-QM

    // V44_EXPORT_BEGIN nid=nYl2inMQNcE
    [SysAbiExport(
        Nid = "nYl2inMQNcE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V123MemberWithMultiPlatformC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3055(CpuContext ctx) => Construct(ctx, 56);
    // V44_EXPORT_END nid=nYl2inMQNcE

    // V44_EXPORT_BEGIN nid=PaCJ0O1vzb4
    [SysAbiExport(
        Nid = "PaCJ0O1vzb4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V123MemberWithMultiPlatform12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3057(CpuContext ctx) => GetValue(ctx, 56, 105, ReturnKind.U64);
    // V44_EXPORT_END nid=PaCJ0O1vzb4

    // V44_EXPORT_BEGIN nid=H80mgXKj4wo
    [SysAbiExport(
        Nid = "H80mgXKj4wo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V123MemberWithMultiPlatform12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3059(CpuContext ctx) => SetValue(ctx, 56, 105, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=H80mgXKj4wo

    // V44_EXPORT_BEGIN nid=3Kdj1+eB7jY
    [SysAbiExport(
        Nid = "3Kdj1+eB7jY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V123MemberWithMultiPlatformD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3062(CpuContext ctx) => Destruct(ctx, 56);
    // V44_EXPORT_END nid=3Kdj1+eB7jY

    // V44_EXPORT_BEGIN nid=m0-OOMOcsKc
    [SysAbiExport(
        Nid = "m0-OOMOcsKc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V123MemberWithMultiPlatformD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3063(CpuContext ctx) => Destruct(ctx, 56);
    // V44_EXPORT_END nid=m0-OOMOcsKc

    // V44_EXPORT_BEGIN nid=Hv8UFPjBI1M
    [SysAbiExport(
        Nid = "Hv8UFPjBI1M",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3080(CpuContext ctx) => Construct(ctx, 57);
    // V44_EXPORT_END nid=Hv8UFPjBI1M

    // V44_EXPORT_BEGIN nid=l6jMZVpYYLs
    [SysAbiExport(
        Nid = "l6jMZVpYYLs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3081(CpuContext ctx) => Construct(ctx, 57);
    // V44_EXPORT_END nid=l6jMZVpYYLs

    // V44_EXPORT_BEGIN nid=1pIUK11v2A8
    [SysAbiExport(
        Nid = "1pIUK11v2A8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody14boolean10IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3082(CpuContext ctx) => IsSet(ctx, 57, 107);
    // V44_EXPORT_END nid=1pIUK11v2A8

    // V44_EXPORT_BEGIN nid=ERDZidsto-o
    [SysAbiExport(
        Nid = "ERDZidsto-o",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean1IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3083(CpuContext ctx) => IsSet(ctx, 57, 106);
    // V44_EXPORT_END nid=ERDZidsto-o

    // V44_EXPORT_BEGIN nid=N7kThMOy1bY
    [SysAbiExport(
        Nid = "N7kThMOy1bY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean2IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3084(CpuContext ctx) => IsSet(ctx, 57, 108);
    // V44_EXPORT_END nid=N7kThMOy1bY

    // V44_EXPORT_BEGIN nid=vxN9vAjnNok
    [SysAbiExport(
        Nid = "vxN9vAjnNok",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean3IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3085(CpuContext ctx) => IsSet(ctx, 57, 109);
    // V44_EXPORT_END nid=vxN9vAjnNok

    // V44_EXPORT_BEGIN nid=Z+IYIl5RcWc
    [SysAbiExport(
        Nid = "Z+IYIl5RcWc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean4IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3086(CpuContext ctx) => IsSet(ctx, 57, 110);
    // V44_EXPORT_END nid=Z+IYIl5RcWc

    // V44_EXPORT_BEGIN nid=Q6fFKJyMxro
    [SysAbiExport(
        Nid = "Q6fFKJyMxro",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean5IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3087(CpuContext ctx) => IsSet(ctx, 57, 111);
    // V44_EXPORT_END nid=Q6fFKJyMxro

    // V44_EXPORT_BEGIN nid=pDnyECvjXNI
    [SysAbiExport(
        Nid = "pDnyECvjXNI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean6IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3088(CpuContext ctx) => IsSet(ctx, 57, 112);
    // V44_EXPORT_END nid=pDnyECvjXNI

    // V44_EXPORT_BEGIN nid=OVM1X4xwX0g
    [SysAbiExport(
        Nid = "OVM1X4xwX0g",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean7IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3089(CpuContext ctx) => IsSet(ctx, 57, 113);
    // V44_EXPORT_END nid=OVM1X4xwX0g

    // V44_EXPORT_BEGIN nid=CxLETQ-8KSc
    [SysAbiExport(
        Nid = "CxLETQ-8KSc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean8IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3090(CpuContext ctx) => IsSet(ctx, 57, 114);
    // V44_EXPORT_END nid=CxLETQ-8KSc

    // V44_EXPORT_BEGIN nid=sSDJ8Zfjadc
    [SysAbiExport(
        Nid = "sSDJ8Zfjadc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13boolean9IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3091(CpuContext ctx) => IsSet(ctx, 57, 115);
    // V44_EXPORT_END nid=sSDJ8Zfjadc

    // V44_EXPORT_BEGIN nid=r2NQzMNLPP0
    [SysAbiExport(
        Nid = "r2NQzMNLPP0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3093(CpuContext ctx) => GetValue(ctx, 57, 106, ReturnKind.Bool);
    // V44_EXPORT_END nid=r2NQzMNLPP0

    // V44_EXPORT_BEGIN nid=+3Q3hFQld3A
    [SysAbiExport(
        Nid = "+3Q3hFQld3A",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody12getBoolean10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3094(CpuContext ctx) => GetValue(ctx, 57, 107, ReturnKind.Bool);
    // V44_EXPORT_END nid=+3Q3hFQld3A

    // V44_EXPORT_BEGIN nid=D5Gx44q5FZo
    [SysAbiExport(
        Nid = "D5Gx44q5FZo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3095(CpuContext ctx) => GetValue(ctx, 57, 108, ReturnKind.Bool);
    // V44_EXPORT_END nid=D5Gx44q5FZo

    // V44_EXPORT_BEGIN nid=P1L-g98OIQY
    [SysAbiExport(
        Nid = "P1L-g98OIQY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3096(CpuContext ctx) => GetValue(ctx, 57, 109, ReturnKind.Bool);
    // V44_EXPORT_END nid=P1L-g98OIQY

    // V44_EXPORT_BEGIN nid=mJK+m+niPq8
    [SysAbiExport(
        Nid = "mJK+m+niPq8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3097(CpuContext ctx) => GetValue(ctx, 57, 110, ReturnKind.Bool);
    // V44_EXPORT_END nid=mJK+m+niPq8

    // V44_EXPORT_BEGIN nid=CYn5f1wClEI
    [SysAbiExport(
        Nid = "CYn5f1wClEI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3098(CpuContext ctx) => GetValue(ctx, 57, 111, ReturnKind.Bool);
    // V44_EXPORT_END nid=CYn5f1wClEI

    // V44_EXPORT_BEGIN nid=b5R9e1XMKW8
    [SysAbiExport(
        Nid = "b5R9e1XMKW8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3099(CpuContext ctx) => GetValue(ctx, 57, 112, ReturnKind.Bool);
    // V44_EXPORT_END nid=b5R9e1XMKW8

    // V44_EXPORT_BEGIN nid=okbwPOT7FM4
    [SysAbiExport(
        Nid = "okbwPOT7FM4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3100(CpuContext ctx) => GetValue(ctx, 57, 113, ReturnKind.Bool);
    // V44_EXPORT_END nid=okbwPOT7FM4

    // V44_EXPORT_BEGIN nid=lkRMoUPDUsI
    [SysAbiExport(
        Nid = "lkRMoUPDUsI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3101(CpuContext ctx) => GetValue(ctx, 57, 114, ReturnKind.Bool);
    // V44_EXPORT_END nid=lkRMoUPDUsI

    // V44_EXPORT_BEGIN nid=k3SYGrPBtpg
    [SysAbiExport(
        Nid = "k3SYGrPBtpg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getBoolean9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3102(CpuContext ctx) => GetValue(ctx, 57, 115, ReturnKind.Bool);
    // V44_EXPORT_END nid=k3SYGrPBtpg

    // V44_EXPORT_BEGIN nid=71RS46Of45w
    [SysAbiExport(
        Nid = "71RS46Of45w",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3103(CpuContext ctx) => GetValue(ctx, 57, 116, ReturnKind.U32);
    // V44_EXPORT_END nid=71RS46Of45w

    // V44_EXPORT_BEGIN nid=fa7w0z2blOo
    [SysAbiExport(
        Nid = "fa7w0z2blOo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody12getInteger10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3104(CpuContext ctx) => GetValue(ctx, 57, 117, ReturnKind.U32);
    // V44_EXPORT_END nid=fa7w0z2blOo

    // V44_EXPORT_BEGIN nid=5+pq5C5vcOk
    [SysAbiExport(
        Nid = "5+pq5C5vcOk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3105(CpuContext ctx) => GetValue(ctx, 57, 118, ReturnKind.U32);
    // V44_EXPORT_END nid=5+pq5C5vcOk

    // V44_EXPORT_BEGIN nid=ud7nv2HX4Ws
    [SysAbiExport(
        Nid = "ud7nv2HX4Ws",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3106(CpuContext ctx) => GetValue(ctx, 57, 119, ReturnKind.U32);
    // V44_EXPORT_END nid=ud7nv2HX4Ws

    // V44_EXPORT_BEGIN nid=2RErB8p4+hw
    [SysAbiExport(
        Nid = "2RErB8p4+hw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3107(CpuContext ctx) => GetValue(ctx, 57, 120, ReturnKind.U32);
    // V44_EXPORT_END nid=2RErB8p4+hw

    // V44_EXPORT_BEGIN nid=y+wn7s8OcUo
    [SysAbiExport(
        Nid = "y+wn7s8OcUo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3108(CpuContext ctx) => GetValue(ctx, 57, 121, ReturnKind.U32);
    // V44_EXPORT_END nid=y+wn7s8OcUo

    // V44_EXPORT_BEGIN nid=BmxAYkNjzW4
    [SysAbiExport(
        Nid = "BmxAYkNjzW4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3109(CpuContext ctx) => GetValue(ctx, 57, 122, ReturnKind.U32);
    // V44_EXPORT_END nid=BmxAYkNjzW4

    // V44_EXPORT_BEGIN nid=bDzs8G+8W9o
    [SysAbiExport(
        Nid = "bDzs8G+8W9o",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3110(CpuContext ctx) => GetValue(ctx, 57, 123, ReturnKind.U32);
    // V44_EXPORT_END nid=bDzs8G+8W9o

    // V44_EXPORT_BEGIN nid=IqNj2WUNlKw
    [SysAbiExport(
        Nid = "IqNj2WUNlKw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3111(CpuContext ctx) => GetValue(ctx, 57, 124, ReturnKind.U32);
    // V44_EXPORT_END nid=IqNj2WUNlKw

    // V44_EXPORT_BEGIN nid=+rVL0oxCqWk
    [SysAbiExport(
        Nid = "+rVL0oxCqWk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11getInteger9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3112(CpuContext ctx) => GetValue(ctx, 57, 125, ReturnKind.U32);
    // V44_EXPORT_END nid=+rVL0oxCqWk

    // V44_EXPORT_BEGIN nid=ybgXBlCu3y4
    [SysAbiExport(
        Nid = "ybgXBlCu3y4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody14integer10IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3123(CpuContext ctx) => IsSet(ctx, 57, 117);
    // V44_EXPORT_END nid=ybgXBlCu3y4

    // V44_EXPORT_BEGIN nid=Bh6Gp0ySKZU
    [SysAbiExport(
        Nid = "Bh6Gp0ySKZU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer1IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3124(CpuContext ctx) => IsSet(ctx, 57, 116);
    // V44_EXPORT_END nid=Bh6Gp0ySKZU

    // V44_EXPORT_BEGIN nid=UPZgNcxZGIs
    [SysAbiExport(
        Nid = "UPZgNcxZGIs",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer2IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3125(CpuContext ctx) => IsSet(ctx, 57, 118);
    // V44_EXPORT_END nid=UPZgNcxZGIs

    // V44_EXPORT_BEGIN nid=ba2H959VLNg
    [SysAbiExport(
        Nid = "ba2H959VLNg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer3IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3126(CpuContext ctx) => IsSet(ctx, 57, 119);
    // V44_EXPORT_END nid=ba2H959VLNg

    // V44_EXPORT_BEGIN nid=gC8yVxSCTFY
    [SysAbiExport(
        Nid = "gC8yVxSCTFY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer4IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3127(CpuContext ctx) => IsSet(ctx, 57, 120);
    // V44_EXPORT_END nid=gC8yVxSCTFY

    // V44_EXPORT_BEGIN nid=6GG5IFre7kg
    [SysAbiExport(
        Nid = "6GG5IFre7kg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer5IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3128(CpuContext ctx) => IsSet(ctx, 57, 121);
    // V44_EXPORT_END nid=6GG5IFre7kg

    // V44_EXPORT_BEGIN nid=BH6N4Bh3BJ4
    [SysAbiExport(
        Nid = "BH6N4Bh3BJ4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer6IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3129(CpuContext ctx) => IsSet(ctx, 57, 122);
    // V44_EXPORT_END nid=BH6N4Bh3BJ4

    // V44_EXPORT_BEGIN nid=Oflukn5jrA8
    [SysAbiExport(
        Nid = "Oflukn5jrA8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer7IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3130(CpuContext ctx) => IsSet(ctx, 57, 123);
    // V44_EXPORT_END nid=Oflukn5jrA8

    // V44_EXPORT_BEGIN nid=zwBb0IHksGo
    [SysAbiExport(
        Nid = "zwBb0IHksGo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer8IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3131(CpuContext ctx) => IsSet(ctx, 57, 124);
    // V44_EXPORT_END nid=zwBb0IHksGo

    // V44_EXPORT_BEGIN nid=KXmWCTY32js
    [SysAbiExport(
        Nid = "KXmWCTY32js",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13integer9IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3132(CpuContext ctx) => IsSet(ctx, 57, 125);
    // V44_EXPORT_END nid=KXmWCTY32js

    // V44_EXPORT_BEGIN nid=L3DTkrs7wNk
    [SysAbiExport(
        Nid = "L3DTkrs7wNk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean1ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3133(CpuContext ctx) => SetValue(ctx, 57, 106, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=L3DTkrs7wNk

    // V44_EXPORT_BEGIN nid=60lM1GvH9bE
    [SysAbiExport(
        Nid = "60lM1GvH9bE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody12setBoolean10ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3134(CpuContext ctx) => SetValue(ctx, 57, 107, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=60lM1GvH9bE

    // V44_EXPORT_BEGIN nid=9+iV7tVBAWA
    [SysAbiExport(
        Nid = "9+iV7tVBAWA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean2ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3135(CpuContext ctx) => SetValue(ctx, 57, 108, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=9+iV7tVBAWA

    // V44_EXPORT_BEGIN nid=2LqYmCT4sio
    [SysAbiExport(
        Nid = "2LqYmCT4sio",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean3ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3136(CpuContext ctx) => SetValue(ctx, 57, 109, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=2LqYmCT4sio

    // V44_EXPORT_BEGIN nid=nEnT4AzTnFM
    [SysAbiExport(
        Nid = "nEnT4AzTnFM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean4ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3137(CpuContext ctx) => SetValue(ctx, 57, 110, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=nEnT4AzTnFM

    // V44_EXPORT_BEGIN nid=XIbPgvWjPMU
    [SysAbiExport(
        Nid = "XIbPgvWjPMU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean5ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3138(CpuContext ctx) => SetValue(ctx, 57, 111, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=XIbPgvWjPMU

    // V44_EXPORT_BEGIN nid=ubRC7kMEocE
    [SysAbiExport(
        Nid = "ubRC7kMEocE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean6ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3139(CpuContext ctx) => SetValue(ctx, 57, 112, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=ubRC7kMEocE

    // V44_EXPORT_BEGIN nid=AAdM44gs+sQ
    [SysAbiExport(
        Nid = "AAdM44gs+sQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean7ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3140(CpuContext ctx) => SetValue(ctx, 57, 113, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=AAdM44gs+sQ

    // V44_EXPORT_BEGIN nid=dduC-QqwiSs
    [SysAbiExport(
        Nid = "dduC-QqwiSs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean8ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3141(CpuContext ctx) => SetValue(ctx, 57, 114, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=dduC-QqwiSs

    // V44_EXPORT_BEGIN nid=k7v2TYeBZkE
    [SysAbiExport(
        Nid = "k7v2TYeBZkE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setBoolean9ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3142(CpuContext ctx) => SetValue(ctx, 57, 115, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=k7v2TYeBZkE

    // V44_EXPORT_BEGIN nid=Yi9pxhGrUXM
    [SysAbiExport(
        Nid = "Yi9pxhGrUXM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger1ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3143(CpuContext ctx) => SetValue(ctx, 57, 116, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=Yi9pxhGrUXM

    // V44_EXPORT_BEGIN nid=O+jxTmjUCFw
    [SysAbiExport(
        Nid = "O+jxTmjUCFw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody12setInteger10ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3144(CpuContext ctx) => SetValue(ctx, 57, 117, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=O+jxTmjUCFw

    // V44_EXPORT_BEGIN nid=gttj6TJVMIE
    [SysAbiExport(
        Nid = "gttj6TJVMIE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger2ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3145(CpuContext ctx) => SetValue(ctx, 57, 118, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=gttj6TJVMIE

    // V44_EXPORT_BEGIN nid=qcL3AzcAYFg
    [SysAbiExport(
        Nid = "qcL3AzcAYFg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger3ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3146(CpuContext ctx) => SetValue(ctx, 57, 119, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=qcL3AzcAYFg

    // V44_EXPORT_BEGIN nid=gG8x2+EFqRE
    [SysAbiExport(
        Nid = "gG8x2+EFqRE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger4ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3147(CpuContext ctx) => SetValue(ctx, 57, 120, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=gG8x2+EFqRE

    // V44_EXPORT_BEGIN nid=FG2XYsInsoI
    [SysAbiExport(
        Nid = "FG2XYsInsoI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger5ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3148(CpuContext ctx) => SetValue(ctx, 57, 121, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=FG2XYsInsoI

    // V44_EXPORT_BEGIN nid=8singq2gbZM
    [SysAbiExport(
        Nid = "8singq2gbZM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger6ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3149(CpuContext ctx) => SetValue(ctx, 57, 122, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=8singq2gbZM

    // V44_EXPORT_BEGIN nid=228r8PUE-38
    [SysAbiExport(
        Nid = "228r8PUE-38",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger7ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3150(CpuContext ctx) => SetValue(ctx, 57, 123, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=228r8PUE-38

    // V44_EXPORT_BEGIN nid=VSv1lvuk7oE
    [SysAbiExport(
        Nid = "VSv1lvuk7oE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger8ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3151(CpuContext ctx) => SetValue(ctx, 57, 124, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=VSv1lvuk7oE

    // V44_EXPORT_BEGIN nid=WmARSMLIsII
    [SysAbiExport(
        Nid = "WmARSMLIsII",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody11setInteger9ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3152(CpuContext ctx) => SetValue(ctx, 57, 125, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=WmARSMLIsII

    // V44_EXPORT_BEGIN nid=H8n8eLcz26w
    [SysAbiExport(
        Nid = "H8n8eLcz26w",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3174(CpuContext ctx) => Unset(ctx, 57, 106);
    // V44_EXPORT_END nid=H8n8eLcz26w

    // V44_EXPORT_BEGIN nid=W6wgr-OJv5Q
    [SysAbiExport(
        Nid = "W6wgr-OJv5Q",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody14unsetBoolean10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3175(CpuContext ctx) => Unset(ctx, 57, 107);
    // V44_EXPORT_END nid=W6wgr-OJv5Q

    // V44_EXPORT_BEGIN nid=zKbDOY04vWM
    [SysAbiExport(
        Nid = "zKbDOY04vWM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3176(CpuContext ctx) => Unset(ctx, 57, 108);
    // V44_EXPORT_END nid=zKbDOY04vWM

    // V44_EXPORT_BEGIN nid=3ZBlQQFUUMQ
    [SysAbiExport(
        Nid = "3ZBlQQFUUMQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3177(CpuContext ctx) => Unset(ctx, 57, 109);
    // V44_EXPORT_END nid=3ZBlQQFUUMQ

    // V44_EXPORT_BEGIN nid=GLDQ5RNh4do
    [SysAbiExport(
        Nid = "GLDQ5RNh4do",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3178(CpuContext ctx) => Unset(ctx, 57, 110);
    // V44_EXPORT_END nid=GLDQ5RNh4do

    // V44_EXPORT_BEGIN nid=-LHI2s5IOOw
    [SysAbiExport(
        Nid = "-LHI2s5IOOw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3179(CpuContext ctx) => Unset(ctx, 57, 111);
    // V44_EXPORT_END nid=-LHI2s5IOOw

    // V44_EXPORT_BEGIN nid=K5VQEvThhCA
    [SysAbiExport(
        Nid = "K5VQEvThhCA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3180(CpuContext ctx) => Unset(ctx, 57, 112);
    // V44_EXPORT_END nid=K5VQEvThhCA

    // V44_EXPORT_BEGIN nid=+W77CCE4Q6M
    [SysAbiExport(
        Nid = "+W77CCE4Q6M",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3181(CpuContext ctx) => Unset(ctx, 57, 113);
    // V44_EXPORT_END nid=+W77CCE4Q6M

    // V44_EXPORT_BEGIN nid=vKIzjL6E2hs
    [SysAbiExport(
        Nid = "vKIzjL6E2hs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3182(CpuContext ctx) => Unset(ctx, 57, 114);
    // V44_EXPORT_END nid=vKIzjL6E2hs

    // V44_EXPORT_BEGIN nid=j5XK45e3Y6M
    [SysAbiExport(
        Nid = "j5XK45e3Y6M",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetBoolean9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3183(CpuContext ctx) => Unset(ctx, 57, 115);
    // V44_EXPORT_END nid=j5XK45e3Y6M

    // V44_EXPORT_BEGIN nid=ATRUUclaAqw
    [SysAbiExport(
        Nid = "ATRUUclaAqw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3184(CpuContext ctx) => Unset(ctx, 57, 116);
    // V44_EXPORT_END nid=ATRUUclaAqw

    // V44_EXPORT_BEGIN nid=9BWGeypaCTA
    [SysAbiExport(
        Nid = "9BWGeypaCTA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody14unsetInteger10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3185(CpuContext ctx) => Unset(ctx, 57, 117);
    // V44_EXPORT_END nid=9BWGeypaCTA

    // V44_EXPORT_BEGIN nid=lKctc5pfx2c
    [SysAbiExport(
        Nid = "lKctc5pfx2c",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3186(CpuContext ctx) => Unset(ctx, 57, 118);
    // V44_EXPORT_END nid=lKctc5pfx2c

    // V44_EXPORT_BEGIN nid=FB6Wl5h3IVU
    [SysAbiExport(
        Nid = "FB6Wl5h3IVU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3187(CpuContext ctx) => Unset(ctx, 57, 119);
    // V44_EXPORT_END nid=FB6Wl5h3IVU

    // V44_EXPORT_BEGIN nid=90m6qsdWl7s
    [SysAbiExport(
        Nid = "90m6qsdWl7s",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3188(CpuContext ctx) => Unset(ctx, 57, 120);
    // V44_EXPORT_END nid=90m6qsdWl7s

    // V44_EXPORT_BEGIN nid=tJFJev3-d60
    [SysAbiExport(
        Nid = "tJFJev3-d60",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3189(CpuContext ctx) => Unset(ctx, 57, 121);
    // V44_EXPORT_END nid=tJFJev3-d60

    // V44_EXPORT_BEGIN nid=DVWEsmHx13U
    [SysAbiExport(
        Nid = "DVWEsmHx13U",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3190(CpuContext ctx) => Unset(ctx, 57, 122);
    // V44_EXPORT_END nid=DVWEsmHx13U

    // V44_EXPORT_BEGIN nid=YP7S9x-Ba50
    [SysAbiExport(
        Nid = "YP7S9x-Ba50",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3191(CpuContext ctx) => Unset(ctx, 57, 123);
    // V44_EXPORT_END nid=YP7S9x-Ba50

    // V44_EXPORT_BEGIN nid=5BIJNOCKfqU
    [SysAbiExport(
        Nid = "5BIJNOCKfqU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3192(CpuContext ctx) => Unset(ctx, 57, 124);
    // V44_EXPORT_END nid=5BIJNOCKfqU

    // V44_EXPORT_BEGIN nid=i+r3hY9gs0A
    [SysAbiExport(
        Nid = "i+r3hY9gs0A",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBody13unsetInteger9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3193(CpuContext ctx) => Unset(ctx, 57, 125);
    // V44_EXPORT_END nid=i+r3hY9gs0A

    // V44_EXPORT_BEGIN nid=MiFP5xEGdw4
    [SysAbiExport(
        Nid = "MiFP5xEGdw4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3204(CpuContext ctx) => Destruct(ctx, 57);
    // V44_EXPORT_END nid=MiFP5xEGdw4

    // V44_EXPORT_BEGIN nid=hEEKjmDJy74
    [SysAbiExport(
        Nid = "hEEKjmDJy74",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V144PatchGameSessionsSearchAttributesRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3205(CpuContext ctx) => Destruct(ctx, 57);
    // V44_EXPORT_END nid=hEEKjmDJy74

    // V44_EXPORT_BEGIN nid=QdVF2oXHoN8
    [SysAbiExport(
        Nid = "QdVF2oXHoN8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3209(CpuContext ctx) => Construct(ctx, 58);
    // V44_EXPORT_END nid=QdVF2oXHoN8

    // V44_EXPORT_BEGIN nid=R00U+nHUD8w
    [SysAbiExport(
        Nid = "R00U+nHUD8w",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3210(CpuContext ctx) => Construct(ctx, 58);
    // V44_EXPORT_END nid=R00U+nHUD8w

    // V44_EXPORT_BEGIN nid=fS518v6hXn4
    [SysAbiExport(
        Nid = "fS518v6hXn4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBody10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3214(CpuContext ctx) => GetValue(ctx, 58, 126, ReturnKind.U32);
    // V44_EXPORT_END nid=fS518v6hXn4

    // V44_EXPORT_BEGIN nid=qUeaaDDDRZA
    [SysAbiExport(
        Nid = "qUeaaDDDRZA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBody12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3215(CpuContext ctx) => IsSet(ctx, 58, 126);
    // V44_EXPORT_END nid=qUeaaDDDRZA

    // V44_EXPORT_BEGIN nid=uLzo94lrfSs
    [SysAbiExport(
        Nid = "uLzo94lrfSs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBody10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3217(CpuContext ctx) => SetValue(ctx, 58, 126, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=uLzo94lrfSs

    // V44_EXPORT_BEGIN nid=kBBS7OZVLzY
    [SysAbiExport(
        Nid = "kBBS7OZVLzY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBody12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3220(CpuContext ctx) => Unset(ctx, 58, 126);
    // V44_EXPORT_END nid=kBBS7OZVLzY

    // V44_EXPORT_BEGIN nid=8p9cStamUIw
    [SysAbiExport(
        Nid = "8p9cStamUIw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3221(CpuContext ctx) => Destruct(ctx, 58);
    // V44_EXPORT_END nid=8p9cStamUIw

    // V44_EXPORT_BEGIN nid=m-zq4GJkoLQ
    [SysAbiExport(
        Nid = "m-zq4GJkoLQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V153PatchGameSessionsSessionIdMembersAccountIdRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3222(CpuContext ctx) => Destruct(ctx, 58);
    // V44_EXPORT_END nid=m-zq4GJkoLQ

    // V44_EXPORT_BEGIN nid=3riNH8Pg8Ro
    [SysAbiExport(
        Nid = "3riNH8Pg8Ro",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3226(CpuContext ctx) => Construct(ctx, 59);
    // V44_EXPORT_END nid=3riNH8Pg8Ro

    // V44_EXPORT_BEGIN nid=Lix8kZ2pg7c
    [SysAbiExport(
        Nid = "Lix8kZ2pg7c",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3227(CpuContext ctx) => Construct(ctx, 59);
    // V44_EXPORT_END nid=Lix8kZ2pg7c

    // V44_EXPORT_BEGIN nid=+p1cW9xUUwk
    [SysAbiExport(
        Nid = "+p1cW9xUUwk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody15getJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3233(CpuContext ctx) => GetValue(ctx, 59, 127, ReturnKind.Bool);
    // V44_EXPORT_END nid=+p1cW9xUUwk

    // V44_EXPORT_BEGIN nid=jy+Nt-Y8XZA
    [SysAbiExport(
        Nid = "jy+Nt-Y8XZA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody13getMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3234(CpuContext ctx) => GetValue(ctx, 59, 128, ReturnKind.U32);
    // V44_EXPORT_END nid=jy+Nt-Y8XZA

    // V44_EXPORT_BEGIN nid=xTMs6eJUqxc
    [SysAbiExport(
        Nid = "xTMs6eJUqxc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody16getMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3235(CpuContext ctx) => GetValue(ctx, 59, 129, ReturnKind.U32);
    // V44_EXPORT_END nid=xTMs6eJUqxc

    // V44_EXPORT_BEGIN nid=0BAA8Pimlcg
    [SysAbiExport(
        Nid = "0BAA8Pimlcg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody13getSearchableEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3236(CpuContext ctx) => GetValue(ctx, 59, 130, ReturnKind.Bool);
    // V44_EXPORT_END nid=0BAA8Pimlcg

    // V44_EXPORT_BEGIN nid=Wri5KLp6Q9Y
    [SysAbiExport(
        Nid = "Wri5KLp6Q9Y",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody17joinDisabledIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3237(CpuContext ctx) => IsSet(ctx, 59, 127);
    // V44_EXPORT_END nid=Wri5KLp6Q9Y

    // V44_EXPORT_BEGIN nid=ghP53NijCWg
    [SysAbiExport(
        Nid = "ghP53NijCWg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody15maxPlayersIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3238(CpuContext ctx) => IsSet(ctx, 59, 128);
    // V44_EXPORT_END nid=ghP53NijCWg

    // V44_EXPORT_BEGIN nid=9OnEOj4zQTI
    [SysAbiExport(
        Nid = "9OnEOj4zQTI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody18maxSpectatorsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3239(CpuContext ctx) => IsSet(ctx, 59, 129);
    // V44_EXPORT_END nid=9OnEOj4zQTI

    // V44_EXPORT_BEGIN nid=EMCFwXJUSa4
    [SysAbiExport(
        Nid = "EMCFwXJUSa4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody15searchableIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3240(CpuContext ctx) => IsSet(ctx, 59, 130);
    // V44_EXPORT_END nid=EMCFwXJUSa4

    // V44_EXPORT_BEGIN nid=-qlyOH8CIzg
    [SysAbiExport(
        Nid = "-qlyOH8CIzg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody15setJoinDisabledERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3243(CpuContext ctx) => SetValue(ctx, 59, 127, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=-qlyOH8CIzg

    // V44_EXPORT_BEGIN nid=guy3X-PEbqk
    [SysAbiExport(
        Nid = "guy3X-PEbqk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody13setMaxPlayersERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3244(CpuContext ctx) => SetValue(ctx, 59, 128, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=guy3X-PEbqk

    // V44_EXPORT_BEGIN nid=bCCKHTeKetw
    [SysAbiExport(
        Nid = "bCCKHTeKetw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody16setMaxSpectatorsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3245(CpuContext ctx) => SetValue(ctx, 59, 129, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=bCCKHTeKetw

    // V44_EXPORT_BEGIN nid=KliDGgkKD-0
    [SysAbiExport(
        Nid = "KliDGgkKD-0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody13setSearchableERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3246(CpuContext ctx) => SetValue(ctx, 59, 130, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=KliDGgkKD-0

    // V44_EXPORT_BEGIN nid=BPdaznYGKzQ
    [SysAbiExport(
        Nid = "BPdaznYGKzQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody17unsetJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3250(CpuContext ctx) => Unset(ctx, 59, 127);
    // V44_EXPORT_END nid=BPdaznYGKzQ

    // V44_EXPORT_BEGIN nid=6Itz1XouY+0
    [SysAbiExport(
        Nid = "6Itz1XouY+0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody15unsetMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3251(CpuContext ctx) => Unset(ctx, 59, 128);
    // V44_EXPORT_END nid=6Itz1XouY+0

    // V44_EXPORT_BEGIN nid=WA-Rz+Fbwqg
    [SysAbiExport(
        Nid = "WA-Rz+Fbwqg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody18unsetMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3252(CpuContext ctx) => Unset(ctx, 59, 129);
    // V44_EXPORT_END nid=WA-Rz+Fbwqg

    // V44_EXPORT_BEGIN nid=WkGWeItozyc
    [SysAbiExport(
        Nid = "WkGWeItozyc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBody15unsetSearchableEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3253(CpuContext ctx) => Unset(ctx, 59, 130);
    // V44_EXPORT_END nid=WkGWeItozyc

    // V44_EXPORT_BEGIN nid=+JhexuCjuLU
    [SysAbiExport(
        Nid = "+JhexuCjuLU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3254(CpuContext ctx) => Destruct(ctx, 59);
    // V44_EXPORT_END nid=+JhexuCjuLU

    // V44_EXPORT_BEGIN nid=eiGYmizCpkk
    [SysAbiExport(
        Nid = "eiGYmizCpkk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V137PatchGameSessionsSessionIdRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3255(CpuContext ctx) => Destruct(ctx, 59);
    // V44_EXPORT_END nid=eiGYmizCpkk

    // V44_EXPORT_BEGIN nid=0Z-zQfu2CZo
    [SysAbiExport(
        Nid = "0Z-zQfu2CZo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3272(CpuContext ctx) => Construct(ctx, 60);
    // V44_EXPORT_END nid=0Z-zQfu2CZo

    // V44_EXPORT_BEGIN nid=mqpatmx34Sg
    [SysAbiExport(
        Nid = "mqpatmx34Sg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3273(CpuContext ctx) => Construct(ctx, 60);
    // V44_EXPORT_END nid=mqpatmx34Sg

    // V44_EXPORT_BEGIN nid=8sMsEpTsUso
    [SysAbiExport(
        Nid = "8sMsEpTsUso",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody15getJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3284(CpuContext ctx) => GetValue(ctx, 60, 131, ReturnKind.Bool);
    // V44_EXPORT_END nid=8sMsEpTsUso

    // V44_EXPORT_BEGIN nid=3LRXwKD7KfI
    [SysAbiExport(
        Nid = "3LRXwKD7KfI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody13getMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3288(CpuContext ctx) => GetValue(ctx, 60, 132, ReturnKind.U32);
    // V44_EXPORT_END nid=3LRXwKD7KfI

    // V44_EXPORT_BEGIN nid=PlBqyQG8tWo
    [SysAbiExport(
        Nid = "PlBqyQG8tWo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody16getMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3289(CpuContext ctx) => GetValue(ctx, 60, 133, ReturnKind.U32);
    // V44_EXPORT_END nid=PlBqyQG8tWo

    // V44_EXPORT_BEGIN nid=RT+HTl2ebBk
    [SysAbiExport(
        Nid = "RT+HTl2ebBk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody16getSwapSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3290(CpuContext ctx) => GetValue(ctx, 60, 134, ReturnKind.Bool);
    // V44_EXPORT_END nid=RT+HTl2ebBk

    // V44_EXPORT_BEGIN nid=pVZmBosjLLI
    [SysAbiExport(
        Nid = "pVZmBosjLLI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody17joinDisabledIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3292(CpuContext ctx) => IsSet(ctx, 60, 131);
    // V44_EXPORT_END nid=pVZmBosjLLI

    // V44_EXPORT_BEGIN nid=roUWFGL+rYY
    [SysAbiExport(
        Nid = "roUWFGL+rYY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody15maxPlayersIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3296(CpuContext ctx) => IsSet(ctx, 60, 132);
    // V44_EXPORT_END nid=roUWFGL+rYY

    // V44_EXPORT_BEGIN nid=6VMcLp042jA
    [SysAbiExport(
        Nid = "6VMcLp042jA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody18maxSpectatorsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3297(CpuContext ctx) => IsSet(ctx, 60, 133);
    // V44_EXPORT_END nid=6VMcLp042jA

    // V44_EXPORT_BEGIN nid=tF4iLLzeCTc
    [SysAbiExport(
        Nid = "tF4iLLzeCTc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody15setJoinDisabledERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3303(CpuContext ctx) => SetValue(ctx, 60, 131, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=tF4iLLzeCTc

    // V44_EXPORT_BEGIN nid=uzgnlW3QnTo
    [SysAbiExport(
        Nid = "uzgnlW3QnTo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody13setMaxPlayersERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3307(CpuContext ctx) => SetValue(ctx, 60, 132, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=uzgnlW3QnTo

    // V44_EXPORT_BEGIN nid=GzqrUd4brhA
    [SysAbiExport(
        Nid = "GzqrUd4brhA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody16setMaxSpectatorsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3308(CpuContext ctx) => SetValue(ctx, 60, 133, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=GzqrUd4brhA

    // V44_EXPORT_BEGIN nid=CWfrxh5cD90
    [SysAbiExport(
        Nid = "CWfrxh5cD90",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody16setSwapSupportedERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3309(CpuContext ctx) => SetValue(ctx, 60, 134, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=CWfrxh5cD90

    // V44_EXPORT_BEGIN nid=XmLaKtWbk90
    [SysAbiExport(
        Nid = "XmLaKtWbk90",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody18swapSupportedIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3310(CpuContext ctx) => IsSet(ctx, 60, 134);
    // V44_EXPORT_END nid=XmLaKtWbk90

    // V44_EXPORT_BEGIN nid=wNsK58YlEw0
    [SysAbiExport(
        Nid = "wNsK58YlEw0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody17unsetJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3317(CpuContext ctx) => Unset(ctx, 60, 131);
    // V44_EXPORT_END nid=wNsK58YlEw0

    // V44_EXPORT_BEGIN nid=+ypdzG3cEIk
    [SysAbiExport(
        Nid = "+ypdzG3cEIk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody15unsetMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3321(CpuContext ctx) => Unset(ctx, 60, 132);
    // V44_EXPORT_END nid=+ypdzG3cEIk

    // V44_EXPORT_BEGIN nid=SfXOhyl4xxU
    [SysAbiExport(
        Nid = "SfXOhyl4xxU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody18unsetMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3322(CpuContext ctx) => Unset(ctx, 60, 133);
    // V44_EXPORT_END nid=SfXOhyl4xxU

    // V44_EXPORT_BEGIN nid=RTD8XIAFqdc
    [SysAbiExport(
        Nid = "RTD8XIAFqdc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBody18unsetSwapSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3323(CpuContext ctx) => Unset(ctx, 60, 134);
    // V44_EXPORT_END nid=RTD8XIAFqdc

    // V44_EXPORT_BEGIN nid=7fHjxMXM+kc
    [SysAbiExport(
        Nid = "7fHjxMXM+kc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3324(CpuContext ctx) => Destruct(ctx, 60);
    // V44_EXPORT_END nid=7fHjxMXM+kc

    // V44_EXPORT_BEGIN nid=lsG3aurAqHg
    [SysAbiExport(
        Nid = "lsG3aurAqHg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V139PatchPlayerSessionsSessionIdRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3325(CpuContext ctx) => Destruct(ctx, 60);
    // V44_EXPORT_END nid=lsG3aurAqHg

    // V44_EXPORT_BEGIN nid=GjQNntzB+Bo
    [SysAbiExport(
        Nid = "GjQNntzB+Bo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForReadC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3342(CpuContext ctx) => Construct(ctx, 61);
    // V44_EXPORT_END nid=GjQNntzB+Bo

    // V44_EXPORT_BEGIN nid=UJY5koADQxk
    [SysAbiExport(
        Nid = "UJY5koADQxk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForReadC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3343(CpuContext ctx) => Construct(ctx, 61);
    // V44_EXPORT_END nid=UJY5koADQxk

    // V44_EXPORT_BEGIN nid=8NUB97h5hMg
    [SysAbiExport(
        Nid = "8NUB97h5hMg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead15getJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3356(CpuContext ctx) => GetValue(ctx, 61, 135, ReturnKind.Bool);
    // V44_EXPORT_END nid=8NUB97h5hMg

    // V44_EXPORT_BEGIN nid=hbD28nqQKoc
    [SysAbiExport(
        Nid = "hbD28nqQKoc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead13getMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3362(CpuContext ctx) => GetValue(ctx, 61, 136, ReturnKind.U32);
    // V44_EXPORT_END nid=hbD28nqQKoc

    // V44_EXPORT_BEGIN nid=USUuOd-dcYQ
    [SysAbiExport(
        Nid = "USUuOd-dcYQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead16getMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3363(CpuContext ctx) => GetValue(ctx, 61, 137, ReturnKind.U32);
    // V44_EXPORT_END nid=USUuOd-dcYQ

    // V44_EXPORT_BEGIN nid=YOwMzBq2Gqg
    [SysAbiExport(
        Nid = "YOwMzBq2Gqg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead18getNonPsnSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3366(CpuContext ctx) => GetValue(ctx, 61, 138, ReturnKind.Bool);
    // V44_EXPORT_END nid=YOwMzBq2Gqg

    // V44_EXPORT_BEGIN nid=Xh5o-FMSmeU
    [SysAbiExport(
        Nid = "Xh5o-FMSmeU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead16getSwapSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3370(CpuContext ctx) => GetValue(ctx, 61, 139, ReturnKind.Bool);
    // V44_EXPORT_END nid=Xh5o-FMSmeU

    // V44_EXPORT_BEGIN nid=9ikEdF-YHFo
    [SysAbiExport(
        Nid = "9ikEdF-YHFo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead17joinDisabledIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3372(CpuContext ctx) => IsSet(ctx, 61, 135);
    // V44_EXPORT_END nid=9ikEdF-YHFo

    // V44_EXPORT_BEGIN nid=mAJiQGwBKOs
    [SysAbiExport(
        Nid = "mAJiQGwBKOs",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead15maxPlayersIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3378(CpuContext ctx) => IsSet(ctx, 61, 136);
    // V44_EXPORT_END nid=mAJiQGwBKOs

    // V44_EXPORT_BEGIN nid=Xc-SooizcFA
    [SysAbiExport(
        Nid = "Xc-SooizcFA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead18maxSpectatorsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3379(CpuContext ctx) => IsSet(ctx, 61, 137);
    // V44_EXPORT_END nid=Xc-SooizcFA

    // V44_EXPORT_BEGIN nid=J8TgBkZ8yq8
    [SysAbiExport(
        Nid = "J8TgBkZ8yq8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead20nonPsnSupportedIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3382(CpuContext ctx) => IsSet(ctx, 61, 138);
    // V44_EXPORT_END nid=J8TgBkZ8yq8

    // V44_EXPORT_BEGIN nid=UDLzu3kE9Uk
    [SysAbiExport(
        Nid = "UDLzu3kE9Uk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead15setJoinDisabledERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3391(CpuContext ctx) => SetValue(ctx, 61, 135, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=UDLzu3kE9Uk

    // V44_EXPORT_BEGIN nid=OWQwWpOwPKI
    [SysAbiExport(
        Nid = "OWQwWpOwPKI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead13setMaxPlayersERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3397(CpuContext ctx) => SetValue(ctx, 61, 136, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=OWQwWpOwPKI

    // V44_EXPORT_BEGIN nid=rPx0crdR-M4
    [SysAbiExport(
        Nid = "rPx0crdR-M4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead16setMaxSpectatorsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3398(CpuContext ctx) => SetValue(ctx, 61, 137, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=rPx0crdR-M4

    // V44_EXPORT_BEGIN nid=fkPuq-1U404
    [SysAbiExport(
        Nid = "fkPuq-1U404",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead18setNonPsnSupportedERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3401(CpuContext ctx) => SetValue(ctx, 61, 138, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=fkPuq-1U404

    // V44_EXPORT_BEGIN nid=5Bv-04tmchM
    [SysAbiExport(
        Nid = "5Bv-04tmchM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead16setSwapSupportedERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3405(CpuContext ctx) => SetValue(ctx, 61, 139, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=5Bv-04tmchM

    // V44_EXPORT_BEGIN nid=PsjIb1R2yXg
    [SysAbiExport(
        Nid = "PsjIb1R2yXg",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead18swapSupportedIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3407(CpuContext ctx) => IsSet(ctx, 61, 139);
    // V44_EXPORT_END nid=PsjIb1R2yXg

    // V44_EXPORT_BEGIN nid=h6IaUPX+Sfc
    [SysAbiExport(
        Nid = "h6IaUPX+Sfc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead17unsetJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3415(CpuContext ctx) => Unset(ctx, 61, 135);
    // V44_EXPORT_END nid=h6IaUPX+Sfc

    // V44_EXPORT_BEGIN nid=8OsvsFluH5A
    [SysAbiExport(
        Nid = "8OsvsFluH5A",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead15unsetMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3421(CpuContext ctx) => Unset(ctx, 61, 136);
    // V44_EXPORT_END nid=8OsvsFluH5A

    // V44_EXPORT_BEGIN nid=YZgmt5Ud5uM
    [SysAbiExport(
        Nid = "YZgmt5Ud5uM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead18unsetMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3422(CpuContext ctx) => Unset(ctx, 61, 137);
    // V44_EXPORT_END nid=YZgmt5Ud5uM

    // V44_EXPORT_BEGIN nid=QsZt9gE5UxI
    [SysAbiExport(
        Nid = "QsZt9gE5UxI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead20unsetNonPsnSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3425(CpuContext ctx) => Unset(ctx, 61, 138);
    // V44_EXPORT_END nid=QsZt9gE5UxI

    // V44_EXPORT_BEGIN nid=aEpSSlROuFo
    [SysAbiExport(
        Nid = "aEpSSlROuFo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForRead18unsetSwapSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3429(CpuContext ctx) => Unset(ctx, 61, 139);
    // V44_EXPORT_END nid=aEpSSlROuFo

    // V44_EXPORT_BEGIN nid=+fpgSfbPPeM
    [SysAbiExport(
        Nid = "+fpgSfbPPeM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForReadD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3430(CpuContext ctx) => Destruct(ctx, 61);
    // V44_EXPORT_END nid=+fpgSfbPPeM

    // V44_EXPORT_BEGIN nid=dWgY+1WxBgU
    [SysAbiExport(
        Nid = "dWgY+1WxBgU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120PlayerSessionForReadD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3431(CpuContext ctx) => Destruct(ctx, 61);
    // V44_EXPORT_END nid=dWgY+1WxBgU

    // V44_EXPORT_BEGIN nid=HNNh2LCUgVA
    [SysAbiExport(
        Nid = "HNNh2LCUgVA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V119PlayerSessionPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3475(CpuContext ctx) => Construct(ctx, 62);
    // V44_EXPORT_END nid=HNNh2LCUgVA

    // V44_EXPORT_BEGIN nid=cjxVyjmiO7Q
    [SysAbiExport(
        Nid = "cjxVyjmiO7Q",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V119PlayerSessionPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3476(CpuContext ctx) => Construct(ctx, 62);
    // V44_EXPORT_END nid=cjxVyjmiO7Q

    // V44_EXPORT_BEGIN nid=T7EoauKK+cM
    [SysAbiExport(
        Nid = "T7EoauKK+cM",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V119PlayerSessionPlayer12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3479(CpuContext ctx) => GetValue(ctx, 62, 140, ReturnKind.U64);
    // V44_EXPORT_END nid=T7EoauKK+cM

    // V44_EXPORT_BEGIN nid=wgsrg1sdaHs
    [SysAbiExport(
        Nid = "wgsrg1sdaHs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V119PlayerSessionPlayer12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3484(CpuContext ctx) => SetValue(ctx, 62, 140, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=wgsrg1sdaHs

    // V44_EXPORT_BEGIN nid=Xkafe+CTK28
    [SysAbiExport(
        Nid = "Xkafe+CTK28",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V119PlayerSessionPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3491(CpuContext ctx) => Destruct(ctx, 62);
    // V44_EXPORT_END nid=Xkafe+CTK28

    // V44_EXPORT_BEGIN nid=cddM72CYeNQ
    [SysAbiExport(
        Nid = "cddM72CYeNQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V119PlayerSessionPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3492(CpuContext ctx) => Destruct(ctx, 62);
    // V44_EXPORT_END nid=cddM72CYeNQ

    // V44_EXPORT_BEGIN nid=ILv6XtwFEXU
    [SysAbiExport(
        Nid = "ILv6XtwFEXU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V122PlayerSessionSpectatorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3507(CpuContext ctx) => Construct(ctx, 63);
    // V44_EXPORT_END nid=ILv6XtwFEXU

    // V44_EXPORT_BEGIN nid=uJ70+H3g6jw
    [SysAbiExport(
        Nid = "uJ70+H3g6jw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V122PlayerSessionSpectatorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3508(CpuContext ctx) => Construct(ctx, 63);
    // V44_EXPORT_END nid=uJ70+H3g6jw

    // V44_EXPORT_BEGIN nid=ZCaq-0g5qJQ
    [SysAbiExport(
        Nid = "ZCaq-0g5qJQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V122PlayerSessionSpectator12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3511(CpuContext ctx) => GetValue(ctx, 63, 141, ReturnKind.U64);
    // V44_EXPORT_END nid=ZCaq-0g5qJQ

    // V44_EXPORT_BEGIN nid=fWOPGmY5Kis
    [SysAbiExport(
        Nid = "fWOPGmY5Kis",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V122PlayerSessionSpectator12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3516(CpuContext ctx) => SetValue(ctx, 63, 141, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=fWOPGmY5Kis

    // V44_EXPORT_BEGIN nid=T1kuF0NLUaw
    [SysAbiExport(
        Nid = "T1kuF0NLUaw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V122PlayerSessionSpectatorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3523(CpuContext ctx) => Destruct(ctx, 63);
    // V44_EXPORT_END nid=T1kuF0NLUaw

    // V44_EXPORT_BEGIN nid=d1QLBV+0Mf4
    [SysAbiExport(
        Nid = "d1QLBV+0Mf4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V122PlayerSessionSpectatorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api3524(CpuContext ctx) => Destruct(ctx, 63);
    // V44_EXPORT_END nid=d1QLBV+0Mf4

    // V44_EXPORT_BEGIN nid=7+vp9qHnefY
    [SysAbiExport(
        Nid = "7+vp9qHnefY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4094(CpuContext ctx) => Construct(ctx, 64);
    // V44_EXPORT_END nid=7+vp9qHnefY

    // V44_EXPORT_BEGIN nid=pGbQivnCv9E
    [SysAbiExport(
        Nid = "pGbQivnCv9E",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4095(CpuContext ctx) => Construct(ctx, 64);
    // V44_EXPORT_END nid=pGbQivnCv9E

    // V44_EXPORT_BEGIN nid=3TMSfgbq0Hw
    [SysAbiExport(
        Nid = "3TMSfgbq0Hw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody14boolean10IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4096(CpuContext ctx) => IsSet(ctx, 64, 143);
    // V44_EXPORT_END nid=3TMSfgbq0Hw

    // V44_EXPORT_BEGIN nid=IFbDzgbVp5U
    [SysAbiExport(
        Nid = "IFbDzgbVp5U",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean1IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4097(CpuContext ctx) => IsSet(ctx, 64, 142);
    // V44_EXPORT_END nid=IFbDzgbVp5U

    // V44_EXPORT_BEGIN nid=HZ42V-ED0to
    [SysAbiExport(
        Nid = "HZ42V-ED0to",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean2IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4098(CpuContext ctx) => IsSet(ctx, 64, 144);
    // V44_EXPORT_END nid=HZ42V-ED0to

    // V44_EXPORT_BEGIN nid=3v9AsJCwW1E
    [SysAbiExport(
        Nid = "3v9AsJCwW1E",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean3IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4099(CpuContext ctx) => IsSet(ctx, 64, 145);
    // V44_EXPORT_END nid=3v9AsJCwW1E

    // V44_EXPORT_BEGIN nid=ZmGaD+bzchU
    [SysAbiExport(
        Nid = "ZmGaD+bzchU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean4IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4100(CpuContext ctx) => IsSet(ctx, 64, 146);
    // V44_EXPORT_END nid=ZmGaD+bzchU

    // V44_EXPORT_BEGIN nid=tDxKK54nviE
    [SysAbiExport(
        Nid = "tDxKK54nviE",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean5IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4101(CpuContext ctx) => IsSet(ctx, 64, 147);
    // V44_EXPORT_END nid=tDxKK54nviE

    // V44_EXPORT_BEGIN nid=ASnQgOs+RIo
    [SysAbiExport(
        Nid = "ASnQgOs+RIo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean6IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4102(CpuContext ctx) => IsSet(ctx, 64, 148);
    // V44_EXPORT_END nid=ASnQgOs+RIo

    // V44_EXPORT_BEGIN nid=j3tmkBq+mvA
    [SysAbiExport(
        Nid = "j3tmkBq+mvA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean7IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4103(CpuContext ctx) => IsSet(ctx, 64, 149);
    // V44_EXPORT_END nid=j3tmkBq+mvA

    // V44_EXPORT_BEGIN nid=QeeZ7AZJlgQ
    [SysAbiExport(
        Nid = "QeeZ7AZJlgQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean8IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4104(CpuContext ctx) => IsSet(ctx, 64, 150);
    // V44_EXPORT_END nid=QeeZ7AZJlgQ

    // V44_EXPORT_BEGIN nid=dQOxdi38pfA
    [SysAbiExport(
        Nid = "dQOxdi38pfA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13boolean9IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4105(CpuContext ctx) => IsSet(ctx, 64, 151);
    // V44_EXPORT_END nid=dQOxdi38pfA

    // V44_EXPORT_BEGIN nid=AgJrWsGmmi4
    [SysAbiExport(
        Nid = "AgJrWsGmmi4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4107(CpuContext ctx) => GetValue(ctx, 64, 142, ReturnKind.Bool);
    // V44_EXPORT_END nid=AgJrWsGmmi4

    // V44_EXPORT_BEGIN nid=1DAagfDSyPM
    [SysAbiExport(
        Nid = "1DAagfDSyPM",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody12getBoolean10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4108(CpuContext ctx) => GetValue(ctx, 64, 143, ReturnKind.Bool);
    // V44_EXPORT_END nid=1DAagfDSyPM

    // V44_EXPORT_BEGIN nid=9xQOIRdEi4M
    [SysAbiExport(
        Nid = "9xQOIRdEi4M",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4109(CpuContext ctx) => GetValue(ctx, 64, 144, ReturnKind.Bool);
    // V44_EXPORT_END nid=9xQOIRdEi4M

    // V44_EXPORT_BEGIN nid=Km9IeqR8Yv4
    [SysAbiExport(
        Nid = "Km9IeqR8Yv4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4110(CpuContext ctx) => GetValue(ctx, 64, 145, ReturnKind.Bool);
    // V44_EXPORT_END nid=Km9IeqR8Yv4

    // V44_EXPORT_BEGIN nid=w3FrVqvZ-Oc
    [SysAbiExport(
        Nid = "w3FrVqvZ-Oc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4111(CpuContext ctx) => GetValue(ctx, 64, 146, ReturnKind.Bool);
    // V44_EXPORT_END nid=w3FrVqvZ-Oc

    // V44_EXPORT_BEGIN nid=Zgjv5SDSRuY
    [SysAbiExport(
        Nid = "Zgjv5SDSRuY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4112(CpuContext ctx) => GetValue(ctx, 64, 147, ReturnKind.Bool);
    // V44_EXPORT_END nid=Zgjv5SDSRuY

    // V44_EXPORT_BEGIN nid=Rw-sJO4mrjI
    [SysAbiExport(
        Nid = "Rw-sJO4mrjI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4113(CpuContext ctx) => GetValue(ctx, 64, 148, ReturnKind.Bool);
    // V44_EXPORT_END nid=Rw-sJO4mrjI

    // V44_EXPORT_BEGIN nid=bC2te-Q6Fdo
    [SysAbiExport(
        Nid = "bC2te-Q6Fdo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4114(CpuContext ctx) => GetValue(ctx, 64, 149, ReturnKind.Bool);
    // V44_EXPORT_END nid=bC2te-Q6Fdo

    // V44_EXPORT_BEGIN nid=1l74I3X1s10
    [SysAbiExport(
        Nid = "1l74I3X1s10",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4115(CpuContext ctx) => GetValue(ctx, 64, 150, ReturnKind.Bool);
    // V44_EXPORT_END nid=1l74I3X1s10

    // V44_EXPORT_BEGIN nid=Od3NXzsLAv0
    [SysAbiExport(
        Nid = "Od3NXzsLAv0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getBoolean9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4116(CpuContext ctx) => GetValue(ctx, 64, 151, ReturnKind.Bool);
    // V44_EXPORT_END nid=Od3NXzsLAv0

    // V44_EXPORT_BEGIN nid=VdK0+zNEH5E
    [SysAbiExport(
        Nid = "VdK0+zNEH5E",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4117(CpuContext ctx) => GetValue(ctx, 64, 152, ReturnKind.U32);
    // V44_EXPORT_END nid=VdK0+zNEH5E

    // V44_EXPORT_BEGIN nid=BcInr0uZ2VI
    [SysAbiExport(
        Nid = "BcInr0uZ2VI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody12getInteger10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4118(CpuContext ctx) => GetValue(ctx, 64, 153, ReturnKind.U32);
    // V44_EXPORT_END nid=BcInr0uZ2VI

    // V44_EXPORT_BEGIN nid=0dOfrES2IUs
    [SysAbiExport(
        Nid = "0dOfrES2IUs",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4119(CpuContext ctx) => GetValue(ctx, 64, 154, ReturnKind.U32);
    // V44_EXPORT_END nid=0dOfrES2IUs

    // V44_EXPORT_BEGIN nid=uNADD2XciMk
    [SysAbiExport(
        Nid = "uNADD2XciMk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4120(CpuContext ctx) => GetValue(ctx, 64, 155, ReturnKind.U32);
    // V44_EXPORT_END nid=uNADD2XciMk

    // V44_EXPORT_BEGIN nid=8OA95knynUU
    [SysAbiExport(
        Nid = "8OA95knynUU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4121(CpuContext ctx) => GetValue(ctx, 64, 156, ReturnKind.U32);
    // V44_EXPORT_END nid=8OA95knynUU

    // V44_EXPORT_BEGIN nid=D5KdoIgekS4
    [SysAbiExport(
        Nid = "D5KdoIgekS4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4122(CpuContext ctx) => GetValue(ctx, 64, 157, ReturnKind.U32);
    // V44_EXPORT_END nid=D5KdoIgekS4

    // V44_EXPORT_BEGIN nid=7aF2OuEoiig
    [SysAbiExport(
        Nid = "7aF2OuEoiig",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4123(CpuContext ctx) => GetValue(ctx, 64, 158, ReturnKind.U32);
    // V44_EXPORT_END nid=7aF2OuEoiig

    // V44_EXPORT_BEGIN nid=6C+j-3zX6Kk
    [SysAbiExport(
        Nid = "6C+j-3zX6Kk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4124(CpuContext ctx) => GetValue(ctx, 64, 159, ReturnKind.U32);
    // V44_EXPORT_END nid=6C+j-3zX6Kk

    // V44_EXPORT_BEGIN nid=dhY8-lRCgPw
    [SysAbiExport(
        Nid = "dhY8-lRCgPw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4125(CpuContext ctx) => GetValue(ctx, 64, 160, ReturnKind.U32);
    // V44_EXPORT_END nid=dhY8-lRCgPw

    // V44_EXPORT_BEGIN nid=RvXewin0NPI
    [SysAbiExport(
        Nid = "RvXewin0NPI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11getInteger9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4126(CpuContext ctx) => GetValue(ctx, 64, 161, ReturnKind.U32);
    // V44_EXPORT_END nid=RvXewin0NPI

    // V44_EXPORT_BEGIN nid=1-giGzb7O1Q
    [SysAbiExport(
        Nid = "1-giGzb7O1Q",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody14integer10IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4137(CpuContext ctx) => IsSet(ctx, 64, 153);
    // V44_EXPORT_END nid=1-giGzb7O1Q

    // V44_EXPORT_BEGIN nid=6+NMbqdqHFE
    [SysAbiExport(
        Nid = "6+NMbqdqHFE",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer1IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4138(CpuContext ctx) => IsSet(ctx, 64, 152);
    // V44_EXPORT_END nid=6+NMbqdqHFE

    // V44_EXPORT_BEGIN nid=tOO2ffhgPHw
    [SysAbiExport(
        Nid = "tOO2ffhgPHw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer2IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4139(CpuContext ctx) => IsSet(ctx, 64, 154);
    // V44_EXPORT_END nid=tOO2ffhgPHw

    // V44_EXPORT_BEGIN nid=Pw+Ub7lnzc8
    [SysAbiExport(
        Nid = "Pw+Ub7lnzc8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer3IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4140(CpuContext ctx) => IsSet(ctx, 64, 155);
    // V44_EXPORT_END nid=Pw+Ub7lnzc8

    // V44_EXPORT_BEGIN nid=8zyHrtXex2E
    [SysAbiExport(
        Nid = "8zyHrtXex2E",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer4IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4141(CpuContext ctx) => IsSet(ctx, 64, 156);
    // V44_EXPORT_END nid=8zyHrtXex2E

    // V44_EXPORT_BEGIN nid=0uiHYKjlCJM
    [SysAbiExport(
        Nid = "0uiHYKjlCJM",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer5IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4142(CpuContext ctx) => IsSet(ctx, 64, 157);
    // V44_EXPORT_END nid=0uiHYKjlCJM

    // V44_EXPORT_BEGIN nid=EYSCmEu6J+8
    [SysAbiExport(
        Nid = "EYSCmEu6J+8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer6IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4143(CpuContext ctx) => IsSet(ctx, 64, 158);
    // V44_EXPORT_END nid=EYSCmEu6J+8

    // V44_EXPORT_BEGIN nid=ZVP30qKoz2g
    [SysAbiExport(
        Nid = "ZVP30qKoz2g",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer7IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4144(CpuContext ctx) => IsSet(ctx, 64, 159);
    // V44_EXPORT_END nid=ZVP30qKoz2g

    // V44_EXPORT_BEGIN nid=pJVmVzElUmQ
    [SysAbiExport(
        Nid = "pJVmVzElUmQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer8IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4145(CpuContext ctx) => IsSet(ctx, 64, 160);
    // V44_EXPORT_END nid=pJVmVzElUmQ

    // V44_EXPORT_BEGIN nid=inYUzxi3gP4
    [SysAbiExport(
        Nid = "inYUzxi3gP4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13integer9IsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4146(CpuContext ctx) => IsSet(ctx, 64, 161);
    // V44_EXPORT_END nid=inYUzxi3gP4

    // V44_EXPORT_BEGIN nid=UsJ+12poR9I
    [SysAbiExport(
        Nid = "UsJ+12poR9I",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean1ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4147(CpuContext ctx) => SetValue(ctx, 64, 142, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=UsJ+12poR9I

    // V44_EXPORT_BEGIN nid=OaLJgYtWtco
    [SysAbiExport(
        Nid = "OaLJgYtWtco",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody12setBoolean10ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4148(CpuContext ctx) => SetValue(ctx, 64, 143, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=OaLJgYtWtco

    // V44_EXPORT_BEGIN nid=pPHjhHqFfFw
    [SysAbiExport(
        Nid = "pPHjhHqFfFw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean2ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4149(CpuContext ctx) => SetValue(ctx, 64, 144, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=pPHjhHqFfFw

    // V44_EXPORT_BEGIN nid=nokk2kTpDBA
    [SysAbiExport(
        Nid = "nokk2kTpDBA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean3ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4150(CpuContext ctx) => SetValue(ctx, 64, 145, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=nokk2kTpDBA

    // V44_EXPORT_BEGIN nid=gTWz90bYZMs
    [SysAbiExport(
        Nid = "gTWz90bYZMs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean4ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4151(CpuContext ctx) => SetValue(ctx, 64, 146, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=gTWz90bYZMs

    // V44_EXPORT_BEGIN nid=p9EIrOs5b5I
    [SysAbiExport(
        Nid = "p9EIrOs5b5I",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean5ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4152(CpuContext ctx) => SetValue(ctx, 64, 147, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=p9EIrOs5b5I

    // V44_EXPORT_BEGIN nid=6cZoyci7-wg
    [SysAbiExport(
        Nid = "6cZoyci7-wg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean6ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4153(CpuContext ctx) => SetValue(ctx, 64, 148, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=6cZoyci7-wg

    // V44_EXPORT_BEGIN nid=dgp9-L4z2j8
    [SysAbiExport(
        Nid = "dgp9-L4z2j8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean7ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4154(CpuContext ctx) => SetValue(ctx, 64, 149, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=dgp9-L4z2j8

    // V44_EXPORT_BEGIN nid=JwxUhvnthCo
    [SysAbiExport(
        Nid = "JwxUhvnthCo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean8ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4155(CpuContext ctx) => SetValue(ctx, 64, 150, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=JwxUhvnthCo

    // V44_EXPORT_BEGIN nid=y7NMLxODL18
    [SysAbiExport(
        Nid = "y7NMLxODL18",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setBoolean9ERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4156(CpuContext ctx) => SetValue(ctx, 64, 151, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=y7NMLxODL18

    // V44_EXPORT_BEGIN nid=pbpdHEY1ch8
    [SysAbiExport(
        Nid = "pbpdHEY1ch8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger1ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4157(CpuContext ctx) => SetValue(ctx, 64, 152, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=pbpdHEY1ch8

    // V44_EXPORT_BEGIN nid=31tkBXveB9M
    [SysAbiExport(
        Nid = "31tkBXveB9M",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody12setInteger10ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4158(CpuContext ctx) => SetValue(ctx, 64, 153, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=31tkBXveB9M

    // V44_EXPORT_BEGIN nid=Bv3PhLc1Rhk
    [SysAbiExport(
        Nid = "Bv3PhLc1Rhk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger2ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4159(CpuContext ctx) => SetValue(ctx, 64, 154, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=Bv3PhLc1Rhk

    // V44_EXPORT_BEGIN nid=+vCoGZv4mtI
    [SysAbiExport(
        Nid = "+vCoGZv4mtI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger3ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4160(CpuContext ctx) => SetValue(ctx, 64, 155, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=+vCoGZv4mtI

    // V44_EXPORT_BEGIN nid=nE55N5ZbNeI
    [SysAbiExport(
        Nid = "nE55N5ZbNeI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger4ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4161(CpuContext ctx) => SetValue(ctx, 64, 156, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=nE55N5ZbNeI

    // V44_EXPORT_BEGIN nid=nyfFQqHZsAQ
    [SysAbiExport(
        Nid = "nyfFQqHZsAQ",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger5ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4162(CpuContext ctx) => SetValue(ctx, 64, 157, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=nyfFQqHZsAQ

    // V44_EXPORT_BEGIN nid=+OlkSeIKOFY
    [SysAbiExport(
        Nid = "+OlkSeIKOFY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger6ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4163(CpuContext ctx) => SetValue(ctx, 64, 158, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=+OlkSeIKOFY

    // V44_EXPORT_BEGIN nid=GcUEOVCIZy8
    [SysAbiExport(
        Nid = "GcUEOVCIZy8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger7ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4164(CpuContext ctx) => SetValue(ctx, 64, 159, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=GcUEOVCIZy8

    // V44_EXPORT_BEGIN nid=ThkHU07+iQk
    [SysAbiExport(
        Nid = "ThkHU07+iQk",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger8ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4165(CpuContext ctx) => SetValue(ctx, 64, 160, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=ThkHU07+iQk

    // V44_EXPORT_BEGIN nid=xLEc4iOjE-U
    [SysAbiExport(
        Nid = "xLEc4iOjE-U",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody11setInteger9ERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4166(CpuContext ctx) => SetValue(ctx, 64, 161, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=xLEc4iOjE-U

    // V44_EXPORT_BEGIN nid=X9Ftp0u4TTc
    [SysAbiExport(
        Nid = "X9Ftp0u4TTc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4188(CpuContext ctx) => Unset(ctx, 64, 142);
    // V44_EXPORT_END nid=X9Ftp0u4TTc

    // V44_EXPORT_BEGIN nid=-VChCq+QRVE
    [SysAbiExport(
        Nid = "-VChCq+QRVE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody14unsetBoolean10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4189(CpuContext ctx) => Unset(ctx, 64, 143);
    // V44_EXPORT_END nid=-VChCq+QRVE

    // V44_EXPORT_BEGIN nid=UblGY0beR58
    [SysAbiExport(
        Nid = "UblGY0beR58",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4190(CpuContext ctx) => Unset(ctx, 64, 144);
    // V44_EXPORT_END nid=UblGY0beR58

    // V44_EXPORT_BEGIN nid=utnW0VWxPKg
    [SysAbiExport(
        Nid = "utnW0VWxPKg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4191(CpuContext ctx) => Unset(ctx, 64, 145);
    // V44_EXPORT_END nid=utnW0VWxPKg

    // V44_EXPORT_BEGIN nid=SONfh19xWGI
    [SysAbiExport(
        Nid = "SONfh19xWGI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4192(CpuContext ctx) => Unset(ctx, 64, 146);
    // V44_EXPORT_END nid=SONfh19xWGI

    // V44_EXPORT_BEGIN nid=+De76KhuKEs
    [SysAbiExport(
        Nid = "+De76KhuKEs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4193(CpuContext ctx) => Unset(ctx, 64, 147);
    // V44_EXPORT_END nid=+De76KhuKEs

    // V44_EXPORT_BEGIN nid=Aidc1CBWfi4
    [SysAbiExport(
        Nid = "Aidc1CBWfi4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4194(CpuContext ctx) => Unset(ctx, 64, 148);
    // V44_EXPORT_END nid=Aidc1CBWfi4

    // V44_EXPORT_BEGIN nid=rHb7R9ccbmA
    [SysAbiExport(
        Nid = "rHb7R9ccbmA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4195(CpuContext ctx) => Unset(ctx, 64, 149);
    // V44_EXPORT_END nid=rHb7R9ccbmA

    // V44_EXPORT_BEGIN nid=3MB9nkbLfDY
    [SysAbiExport(
        Nid = "3MB9nkbLfDY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4196(CpuContext ctx) => Unset(ctx, 64, 150);
    // V44_EXPORT_END nid=3MB9nkbLfDY

    // V44_EXPORT_BEGIN nid=k1Z9vz+VFMM
    [SysAbiExport(
        Nid = "k1Z9vz+VFMM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetBoolean9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4197(CpuContext ctx) => Unset(ctx, 64, 151);
    // V44_EXPORT_END nid=k1Z9vz+VFMM

    // V44_EXPORT_BEGIN nid=7Lj2ga9vDCM
    [SysAbiExport(
        Nid = "7Lj2ga9vDCM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4198(CpuContext ctx) => Unset(ctx, 64, 152);
    // V44_EXPORT_END nid=7Lj2ga9vDCM

    // V44_EXPORT_BEGIN nid=uT4hP43dsiU
    [SysAbiExport(
        Nid = "uT4hP43dsiU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody14unsetInteger10Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4199(CpuContext ctx) => Unset(ctx, 64, 153);
    // V44_EXPORT_END nid=uT4hP43dsiU

    // V44_EXPORT_BEGIN nid=6QeVyxMbKgg
    [SysAbiExport(
        Nid = "6QeVyxMbKgg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4200(CpuContext ctx) => Unset(ctx, 64, 154);
    // V44_EXPORT_END nid=6QeVyxMbKgg

    // V44_EXPORT_BEGIN nid=GhZeEvhE2q4
    [SysAbiExport(
        Nid = "GhZeEvhE2q4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger3Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4201(CpuContext ctx) => Unset(ctx, 64, 155);
    // V44_EXPORT_END nid=GhZeEvhE2q4

    // V44_EXPORT_BEGIN nid=gL4J2k2+o8A
    [SysAbiExport(
        Nid = "gL4J2k2+o8A",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger4Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4202(CpuContext ctx) => Unset(ctx, 64, 156);
    // V44_EXPORT_END nid=gL4J2k2+o8A

    // V44_EXPORT_BEGIN nid=54Awhl1UJw4
    [SysAbiExport(
        Nid = "54Awhl1UJw4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger5Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4203(CpuContext ctx) => Unset(ctx, 64, 157);
    // V44_EXPORT_END nid=54Awhl1UJw4

    // V44_EXPORT_BEGIN nid=BEliazuCx3s
    [SysAbiExport(
        Nid = "BEliazuCx3s",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger6Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4204(CpuContext ctx) => Unset(ctx, 64, 158);
    // V44_EXPORT_END nid=BEliazuCx3s

    // V44_EXPORT_BEGIN nid=bGY41uf2SfI
    [SysAbiExport(
        Nid = "bGY41uf2SfI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger7Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4205(CpuContext ctx) => Unset(ctx, 64, 159);
    // V44_EXPORT_END nid=bGY41uf2SfI

    // V44_EXPORT_BEGIN nid=ODRrJdEIV94
    [SysAbiExport(
        Nid = "ODRrJdEIV94",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger8Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4206(CpuContext ctx) => Unset(ctx, 64, 160);
    // V44_EXPORT_END nid=ODRrJdEIV94

    // V44_EXPORT_BEGIN nid=AOw2gfsSN-8
    [SysAbiExport(
        Nid = "AOw2gfsSN-8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBody13unsetInteger9Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4207(CpuContext ctx) => Unset(ctx, 64, 161);
    // V44_EXPORT_END nid=AOw2gfsSN-8

    // V44_EXPORT_BEGIN nid=r8HE653o+HI
    [SysAbiExport(
        Nid = "r8HE653o+HI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4218(CpuContext ctx) => Destruct(ctx, 64);
    // V44_EXPORT_END nid=r8HE653o+HI

    // V44_EXPORT_BEGIN nid=xubh1B6X354
    [SysAbiExport(
        Nid = "xubh1B6X354",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V142PutGameSessionsSearchAttributesRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4219(CpuContext ctx) => Destruct(ctx, 64);
    // V44_EXPORT_END nid=xubh1B6X354

    // V44_EXPORT_BEGIN nid=QpXrlLWSrO0
    [SysAbiExport(
        Nid = "QpXrlLWSrO0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V143PutPlayerSessionsSessionIdLeaderRequestBodyC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4234(CpuContext ctx) => Construct(ctx, 65);
    // V44_EXPORT_END nid=QpXrlLWSrO0

    // V44_EXPORT_BEGIN nid=tLCK4GJe9jY
    [SysAbiExport(
        Nid = "tLCK4GJe9jY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V143PutPlayerSessionsSessionIdLeaderRequestBodyC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4235(CpuContext ctx) => Construct(ctx, 65);
    // V44_EXPORT_END nid=tLCK4GJe9jY

    // V44_EXPORT_BEGIN nid=BhS3iiQHCVQ
    [SysAbiExport(
        Nid = "BhS3iiQHCVQ",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V143PutPlayerSessionsSessionIdLeaderRequestBody12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4237(CpuContext ctx) => GetValue(ctx, 65, 162, ReturnKind.U64);
    // V44_EXPORT_END nid=BhS3iiQHCVQ

    // V44_EXPORT_BEGIN nid=59E95MocP2Q
    [SysAbiExport(
        Nid = "59E95MocP2Q",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V143PutPlayerSessionsSessionIdLeaderRequestBody12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4239(CpuContext ctx) => SetValue(ctx, 65, 162, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=59E95MocP2Q

    // V44_EXPORT_BEGIN nid=OMq2WoEtX+w
    [SysAbiExport(
        Nid = "OMq2WoEtX+w",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V143PutPlayerSessionsSessionIdLeaderRequestBodyD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4242(CpuContext ctx) => Destruct(ctx, 65);
    // V44_EXPORT_END nid=OMq2WoEtX+w

    // V44_EXPORT_BEGIN nid=y3iNnPlPfyw
    [SysAbiExport(
        Nid = "y3iNnPlPfyw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V143PutPlayerSessionsSessionIdLeaderRequestBodyD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4243(CpuContext ctx) => Destruct(ctx, 65);
    // V44_EXPORT_END nid=y3iNnPlPfyw

    // V44_EXPORT_BEGIN nid=uHtBrJrJv4I
    [SysAbiExport(
        Nid = "uHtBrJrJv4I",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V114RepresentativeC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4247(CpuContext ctx) => Construct(ctx, 66);
    // V44_EXPORT_END nid=uHtBrJrJv4I

    // V44_EXPORT_BEGIN nid=xZH-GUWHsLc
    [SysAbiExport(
        Nid = "xZH-GUWHsLc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V114RepresentativeC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4248(CpuContext ctx) => Construct(ctx, 66);
    // V44_EXPORT_END nid=xZH-GUWHsLc

    // V44_EXPORT_BEGIN nid=UsoNZ5gxEuo
    [SysAbiExport(
        Nid = "UsoNZ5gxEuo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V114Representative12getAccountIdEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4250(CpuContext ctx) => GetValue(ctx, 66, 163, ReturnKind.U64);
    // V44_EXPORT_END nid=UsoNZ5gxEuo

    // V44_EXPORT_BEGIN nid=v4eUw70y6uc
    [SysAbiExport(
        Nid = "v4eUw70y6uc",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V114Representative12setAccountIdERKm",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4253(CpuContext ctx) => SetValue(ctx, 66, 163, ValueSource.U64Ref, false);
    // V44_EXPORT_END nid=v4eUw70y6uc

    // V44_EXPORT_BEGIN nid=Lq7ryOJ78Sg
    [SysAbiExport(
        Nid = "Lq7ryOJ78Sg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V114RepresentativeD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4257(CpuContext ctx) => Destruct(ctx, 66);
    // V44_EXPORT_END nid=Lq7ryOJ78Sg

    // V44_EXPORT_BEGIN nid=Wa7dSfVTJLM
    [SysAbiExport(
        Nid = "Wa7dSfVTJLM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V114RepresentativeD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4258(CpuContext ctx) => Destruct(ctx, 66);
    // V44_EXPORT_END nid=Wa7dSfVTJLM

    // V44_EXPORT_BEGIN nid=MhfikztCjT4
    [SysAbiExport(
        Nid = "MhfikztCjT4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSessionC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4298(CpuContext ctx) => Construct(ctx, 67);
    // V44_EXPORT_END nid=MhfikztCjT4

    // V44_EXPORT_BEGIN nid=rVZe903G-BU
    [SysAbiExport(
        Nid = "rVZe903G-BU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSessionC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4299(CpuContext ctx) => Construct(ctx, 67);
    // V44_EXPORT_END nid=rVZe903G-BU

    // V44_EXPORT_BEGIN nid=dkU553Qf+F0
    [SysAbiExport(
        Nid = "dkU553Qf+F0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession15getJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4305(CpuContext ctx) => GetValue(ctx, 67, 164, ReturnKind.Bool);
    // V44_EXPORT_END nid=dkU553Qf+F0

    // V44_EXPORT_BEGIN nid=C4g29wO9igs
    [SysAbiExport(
        Nid = "C4g29wO9igs",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession13getMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4306(CpuContext ctx) => GetValue(ctx, 67, 165, ReturnKind.U32);
    // V44_EXPORT_END nid=C4g29wO9igs

    // V44_EXPORT_BEGIN nid=nI0xthFylNU
    [SysAbiExport(
        Nid = "nI0xthFylNU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession16getMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4307(CpuContext ctx) => GetValue(ctx, 67, 166, ReturnKind.U32);
    // V44_EXPORT_END nid=nI0xthFylNU

    // V44_EXPORT_BEGIN nid=ItZHQ9B51QI
    [SysAbiExport(
        Nid = "ItZHQ9B51QI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession28getReservationTimeoutSecondsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4309(CpuContext ctx) => GetValue(ctx, 67, 167, ReturnKind.U32);
    // V44_EXPORT_END nid=ItZHQ9B51QI

    // V44_EXPORT_BEGIN nid=Ta8UauHm2Xo
    [SysAbiExport(
        Nid = "Ta8UauHm2Xo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession13getSearchableEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4312(CpuContext ctx) => GetValue(ctx, 67, 168, ReturnKind.Bool);
    // V44_EXPORT_END nid=Ta8UauHm2Xo

    // V44_EXPORT_BEGIN nid=zpVCZPtswnc
    [SysAbiExport(
        Nid = "zpVCZPtswnc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession19getUsePlayerSessionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4314(CpuContext ctx) => GetValue(ctx, 67, 169, ReturnKind.Bool);
    // V44_EXPORT_END nid=zpVCZPtswnc

    // V44_EXPORT_BEGIN nid=iZZ7g7Tge58
    [SysAbiExport(
        Nid = "iZZ7g7Tge58",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession17joinDisabledIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4315(CpuContext ctx) => IsSet(ctx, 67, 164);
    // V44_EXPORT_END nid=iZZ7g7Tge58

    // V44_EXPORT_BEGIN nid=0rE9gw7K-bI
    [SysAbiExport(
        Nid = "0rE9gw7K-bI",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession18maxSpectatorsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4316(CpuContext ctx) => IsSet(ctx, 67, 166);
    // V44_EXPORT_END nid=0rE9gw7K-bI

    // V44_EXPORT_BEGIN nid=733IvkSQ3tY
    [SysAbiExport(
        Nid = "733IvkSQ3tY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession30reservationTimeoutSecondsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4317(CpuContext ctx) => IsSet(ctx, 67, 167);
    // V44_EXPORT_END nid=733IvkSQ3tY

    // V44_EXPORT_BEGIN nid=vb2lzbfKjNM
    [SysAbiExport(
        Nid = "vb2lzbfKjNM",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession15searchableIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4320(CpuContext ctx) => IsSet(ctx, 67, 168);
    // V44_EXPORT_END nid=vb2lzbfKjNM

    // V44_EXPORT_BEGIN nid=t4FA0L6NjqY
    [SysAbiExport(
        Nid = "t4FA0L6NjqY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession15setJoinDisabledERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4323(CpuContext ctx) => SetValue(ctx, 67, 164, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=t4FA0L6NjqY

    // V44_EXPORT_BEGIN nid=2M7akX+bJTw
    [SysAbiExport(
        Nid = "2M7akX+bJTw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession13setMaxPlayersERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4324(CpuContext ctx) => SetValue(ctx, 67, 165, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=2M7akX+bJTw

    // V44_EXPORT_BEGIN nid=SyilEZ5n3wU
    [SysAbiExport(
        Nid = "SyilEZ5n3wU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession16setMaxSpectatorsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4325(CpuContext ctx) => SetValue(ctx, 67, 166, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=SyilEZ5n3wU

    // V44_EXPORT_BEGIN nid=1xoLMLSYmE8
    [SysAbiExport(
        Nid = "1xoLMLSYmE8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession28setReservationTimeoutSecondsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4327(CpuContext ctx) => SetValue(ctx, 67, 167, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=1xoLMLSYmE8

    // V44_EXPORT_BEGIN nid=36UasLgAHg8
    [SysAbiExport(
        Nid = "36UasLgAHg8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession13setSearchableERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4330(CpuContext ctx) => SetValue(ctx, 67, 168, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=36UasLgAHg8

    // V44_EXPORT_BEGIN nid=lFoCvh0UOew
    [SysAbiExport(
        Nid = "lFoCvh0UOew",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession19setUsePlayerSessionERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4332(CpuContext ctx) => SetValue(ctx, 67, 169, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=lFoCvh0UOew

    // V44_EXPORT_BEGIN nid=nsBS3-CH8uw
    [SysAbiExport(
        Nid = "nsBS3-CH8uw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession17unsetJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4336(CpuContext ctx) => Unset(ctx, 67, 164);
    // V44_EXPORT_END nid=nsBS3-CH8uw

    // V44_EXPORT_BEGIN nid=6k0X7NGUGkw
    [SysAbiExport(
        Nid = "6k0X7NGUGkw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession18unsetMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4337(CpuContext ctx) => Unset(ctx, 67, 166);
    // V44_EXPORT_END nid=6k0X7NGUGkw

    // V44_EXPORT_BEGIN nid=zuCubBF5OZ8
    [SysAbiExport(
        Nid = "zuCubBF5OZ8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession30unsetReservationTimeoutSecondsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4338(CpuContext ctx) => Unset(ctx, 67, 167);
    // V44_EXPORT_END nid=zuCubBF5OZ8

    // V44_EXPORT_BEGIN nid=1gWEHIaOQh0
    [SysAbiExport(
        Nid = "1gWEHIaOQh0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession15unsetSearchableEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4341(CpuContext ctx) => Unset(ctx, 67, 168);
    // V44_EXPORT_END nid=1gWEHIaOQh0

    // V44_EXPORT_BEGIN nid=kwrN3bDhOUs
    [SysAbiExport(
        Nid = "kwrN3bDhOUs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSession21unsetUsePlayerSessionEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4342(CpuContext ctx) => Unset(ctx, 67, 169);
    // V44_EXPORT_END nid=kwrN3bDhOUs

    // V44_EXPORT_BEGIN nid=lAa689pKyF0
    [SysAbiExport(
        Nid = "lAa689pKyF0",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V118RequestGameSession21usePlayerSessionIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4343(CpuContext ctx) => IsSet(ctx, 67, 169);
    // V44_EXPORT_END nid=lAa689pKyF0

    // V44_EXPORT_BEGIN nid=07drtGkizRA
    [SysAbiExport(
        Nid = "07drtGkizRA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSessionD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4344(CpuContext ctx) => Destruct(ctx, 67);
    // V44_EXPORT_END nid=07drtGkizRA

    // V44_EXPORT_BEGIN nid=eUFtsxmi2p0
    [SysAbiExport(
        Nid = "eUFtsxmi2p0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V118RequestGameSessionD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4345(CpuContext ctx) => Destruct(ctx, 67);
    // V44_EXPORT_END nid=eUFtsxmi2p0

    // V44_EXPORT_BEGIN nid=3QMXeS1mJG8
    [SysAbiExport(
        Nid = "3QMXeS1mJG8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4360(CpuContext ctx) => Construct(ctx, 68);
    // V44_EXPORT_END nid=3QMXeS1mJG8

    // V44_EXPORT_BEGIN nid=KraCNmh2LzA
    [SysAbiExport(
        Nid = "KraCNmh2LzA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4361(CpuContext ctx) => Construct(ctx, 68);
    // V44_EXPORT_END nid=KraCNmh2LzA

    // V44_EXPORT_BEGIN nid=0q8I0P9tIl8
    [SysAbiExport(
        Nid = "0q8I0P9tIl8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayer10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4367(CpuContext ctx) => GetValue(ctx, 68, 170, ReturnKind.U32);
    // V44_EXPORT_END nid=0q8I0P9tIl8

    // V44_EXPORT_BEGIN nid=v9Evh4f3TrY
    [SysAbiExport(
        Nid = "v9Evh4f3TrY",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayer12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4371(CpuContext ctx) => IsSet(ctx, 68, 170);
    // V44_EXPORT_END nid=v9Evh4f3TrY

    // V44_EXPORT_BEGIN nid=95x6M5HT8IY
    [SysAbiExport(
        Nid = "95x6M5HT8IY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayer10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4376(CpuContext ctx) => SetValue(ctx, 68, 170, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=95x6M5HT8IY

    // V44_EXPORT_BEGIN nid=87y0cjK5WrY
    [SysAbiExport(
        Nid = "87y0cjK5WrY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayer12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4382(CpuContext ctx) => Unset(ctx, 68, 170);
    // V44_EXPORT_END nid=87y0cjK5WrY

    // V44_EXPORT_BEGIN nid=7OGapdx1hQM
    [SysAbiExport(
        Nid = "7OGapdx1hQM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4384(CpuContext ctx) => Destruct(ctx, 68);
    // V44_EXPORT_END nid=7OGapdx1hQM

    // V44_EXPORT_BEGIN nid=Scedp5ayLsM
    [SysAbiExport(
        Nid = "Scedp5ayLsM",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V124RequestGameSessionPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4385(CpuContext ctx) => Destruct(ctx, 68);
    // V44_EXPORT_END nid=Scedp5ayLsM

    // V44_EXPORT_BEGIN nid=1C2mJi3KfJg
    [SysAbiExport(
        Nid = "1C2mJi3KfJg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectatorC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4389(CpuContext ctx) => Construct(ctx, 69);
    // V44_EXPORT_END nid=1C2mJi3KfJg

    // V44_EXPORT_BEGIN nid=g1wnjq7kgwE
    [SysAbiExport(
        Nid = "g1wnjq7kgwE",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectatorC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4390(CpuContext ctx) => Construct(ctx, 69);
    // V44_EXPORT_END nid=g1wnjq7kgwE

    // V44_EXPORT_BEGIN nid=FF7t-vxbO9I
    [SysAbiExport(
        Nid = "FF7t-vxbO9I",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectator10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4395(CpuContext ctx) => GetValue(ctx, 69, 171, ReturnKind.U32);
    // V44_EXPORT_END nid=FF7t-vxbO9I

    // V44_EXPORT_BEGIN nid=VEaaAp9bSO4
    [SysAbiExport(
        Nid = "VEaaAp9bSO4",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectator12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4398(CpuContext ctx) => IsSet(ctx, 69, 171);
    // V44_EXPORT_END nid=VEaaAp9bSO4

    // V44_EXPORT_BEGIN nid=BzZob2Qk4B0
    [SysAbiExport(
        Nid = "BzZob2Qk4B0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectator10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4402(CpuContext ctx) => SetValue(ctx, 69, 171, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=BzZob2Qk4B0

    // V44_EXPORT_BEGIN nid=3waAScJjcZw
    [SysAbiExport(
        Nid = "3waAScJjcZw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectator12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4407(CpuContext ctx) => Unset(ctx, 69, 171);
    // V44_EXPORT_END nid=3waAScJjcZw

    // V44_EXPORT_BEGIN nid=SKvobx84-2Y
    [SysAbiExport(
        Nid = "SKvobx84-2Y",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectatorD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4409(CpuContext ctx) => Destruct(ctx, 69);
    // V44_EXPORT_END nid=SKvobx84-2Y

    // V44_EXPORT_BEGIN nid=pUgVd0pfnz4
    [SysAbiExport(
        Nid = "pUgVd0pfnz4",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V127RequestGameSessionSpectatorD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4410(CpuContext ctx) => Destruct(ctx, 69);
    // V44_EXPORT_END nid=pUgVd0pfnz4

    // V44_EXPORT_BEGIN nid=6jlFAPd4jGY
    [SysAbiExport(
        Nid = "6jlFAPd4jGY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayerC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4414(CpuContext ctx) => Construct(ctx, 70);
    // V44_EXPORT_END nid=6jlFAPd4jGY

    // V44_EXPORT_BEGIN nid=fvzhAtX7xbY
    [SysAbiExport(
        Nid = "fvzhAtX7xbY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayerC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4415(CpuContext ctx) => Construct(ctx, 70);
    // V44_EXPORT_END nid=fvzhAtX7xbY

    // V44_EXPORT_BEGIN nid=WT4k6XEZ8Eo
    [SysAbiExport(
        Nid = "WT4k6XEZ8Eo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayer10getNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4421(CpuContext ctx) => GetValue(ctx, 70, 172, ReturnKind.U32);
    // V44_EXPORT_END nid=WT4k6XEZ8Eo

    // V44_EXPORT_BEGIN nid=HYwqB4wv0kw
    [SysAbiExport(
        Nid = "HYwqB4wv0kw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayer12natTypeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4425(CpuContext ctx) => IsSet(ctx, 70, 172);
    // V44_EXPORT_END nid=HYwqB4wv0kw

    // V44_EXPORT_BEGIN nid=CoiBwv7Gerg
    [SysAbiExport(
        Nid = "CoiBwv7Gerg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayer10setNatTypeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4430(CpuContext ctx) => SetValue(ctx, 70, 172, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=CoiBwv7Gerg

    // V44_EXPORT_BEGIN nid=kRms03n0VdU
    [SysAbiExport(
        Nid = "kRms03n0VdU",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayer12unsetNatTypeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4436(CpuContext ctx) => Unset(ctx, 70, 172);
    // V44_EXPORT_END nid=kRms03n0VdU

    // V44_EXPORT_BEGIN nid=73SV5VnRI68
    [SysAbiExport(
        Nid = "73SV5VnRI68",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayerD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4438(CpuContext ctx) => Destruct(ctx, 70);
    // V44_EXPORT_END nid=73SV5VnRI68

    // V44_EXPORT_BEGIN nid=XxoF7-Yj5Pg
    [SysAbiExport(
        Nid = "XxoF7-Yj5Pg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V128RequestJoinGameSessionPlayerD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4439(CpuContext ctx) => Destruct(ctx, 70);
    // V44_EXPORT_END nid=XxoF7-Yj5Pg

    // V44_EXPORT_BEGIN nid=AZCGnCb-TH8
    [SysAbiExport(
        Nid = "AZCGnCb-TH8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSessionC2EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4443(CpuContext ctx) => Construct(ctx, 71);
    // V44_EXPORT_END nid=AZCGnCb-TH8

    // V44_EXPORT_BEGIN nid=Rp4f0JT5fv8
    [SysAbiExport(
        Nid = "Rp4f0JT5fv8",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSessionC1EPNS1_6Common10LibContextE",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4444(CpuContext ctx) => Construct(ctx, 71);
    // V44_EXPORT_END nid=Rp4f0JT5fv8

    // V44_EXPORT_BEGIN nid=tFT0Peb2BCU
    [SysAbiExport(
        Nid = "tFT0Peb2BCU",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession19expirationTimeIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4449(CpuContext ctx) => IsSet(ctx, 71, 173);
    // V44_EXPORT_END nid=tFT0Peb2BCU

    // V44_EXPORT_BEGIN nid=Op4FMZd6Ej8
    [SysAbiExport(
        Nid = "Op4FMZd6Ej8",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession17getExpirationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4455(CpuContext ctx) => GetValue(ctx, 71, 173, ReturnKind.U32);
    // V44_EXPORT_END nid=Op4FMZd6Ej8

    // V44_EXPORT_BEGIN nid=huBRvuH7acw
    [SysAbiExport(
        Nid = "huBRvuH7acw",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession15getJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4457(CpuContext ctx) => GetValue(ctx, 71, 174, ReturnKind.Bool);
    // V44_EXPORT_END nid=huBRvuH7acw

    // V44_EXPORT_BEGIN nid=+hDIeI+jHYs
    [SysAbiExport(
        Nid = "+hDIeI+jHYs",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession13getMaxPlayersEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4461(CpuContext ctx) => GetValue(ctx, 71, 175, ReturnKind.U32);
    // V44_EXPORT_END nid=+hDIeI+jHYs

    // V44_EXPORT_BEGIN nid=gtYJOTEcCrc
    [SysAbiExport(
        Nid = "gtYJOTEcCrc",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession16getMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4462(CpuContext ctx) => GetValue(ctx, 71, 176, ReturnKind.U32);
    // V44_EXPORT_END nid=gtYJOTEcCrc

    // V44_EXPORT_BEGIN nid=kaasopY4BaA
    [SysAbiExport(
        Nid = "kaasopY4BaA",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession18getNonPsnSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4464(CpuContext ctx) => GetValue(ctx, 71, 177, ReturnKind.Bool);
    // V44_EXPORT_END nid=kaasopY4BaA

    // V44_EXPORT_BEGIN nid=p38FKNLfCik
    [SysAbiExport(
        Nid = "p38FKNLfCik",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession16getSwapSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4466(CpuContext ctx) => GetValue(ctx, 71, 178, ReturnKind.Bool);
    // V44_EXPORT_END nid=p38FKNLfCik

    // V44_EXPORT_BEGIN nid=bWzx-teZAOo
    [SysAbiExport(
        Nid = "bWzx-teZAOo",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession17joinDisabledIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4468(CpuContext ctx) => IsSet(ctx, 71, 174);
    // V44_EXPORT_END nid=bWzx-teZAOo

    // V44_EXPORT_BEGIN nid=9khd40gnX3s
    [SysAbiExport(
        Nid = "9khd40gnX3s",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession18maxSpectatorsIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4471(CpuContext ctx) => IsSet(ctx, 71, 176);
    // V44_EXPORT_END nid=9khd40gnX3s

    // V44_EXPORT_BEGIN nid=mU-QJxULXgk
    [SysAbiExport(
        Nid = "mU-QJxULXgk",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession20nonPsnSupportedIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4472(CpuContext ctx) => IsSet(ctx, 71, 177);
    // V44_EXPORT_END nid=mU-QJxULXgk

    // V44_EXPORT_BEGIN nid=-XhyxXB0cYg
    [SysAbiExport(
        Nid = "-XhyxXB0cYg",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession17setExpirationTimeERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4477(CpuContext ctx) => SetValue(ctx, 71, 173, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=-XhyxXB0cYg

    // V44_EXPORT_BEGIN nid=8O-6RHUTD7k
    [SysAbiExport(
        Nid = "8O-6RHUTD7k",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession15setJoinDisabledERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4479(CpuContext ctx) => SetValue(ctx, 71, 174, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=8O-6RHUTD7k

    // V44_EXPORT_BEGIN nid=AiazZsMHSfs
    [SysAbiExport(
        Nid = "AiazZsMHSfs",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession13setMaxPlayersERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4483(CpuContext ctx) => SetValue(ctx, 71, 175, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=AiazZsMHSfs

    // V44_EXPORT_BEGIN nid=+oqyRiwxW18
    [SysAbiExport(
        Nid = "+oqyRiwxW18",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession16setMaxSpectatorsERKi",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4484(CpuContext ctx) => SetValue(ctx, 71, 176, ValueSource.U32Ref, false);
    // V44_EXPORT_END nid=+oqyRiwxW18

    // V44_EXPORT_BEGIN nid=SBOI-vjWAPY
    [SysAbiExport(
        Nid = "SBOI-vjWAPY",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession18setNonPsnSupportedERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4486(CpuContext ctx) => SetValue(ctx, 71, 177, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=SBOI-vjWAPY

    // V44_EXPORT_BEGIN nid=8C36kDPJiS0
    [SysAbiExport(
        Nid = "8C36kDPJiS0",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession16setSwapSupportedERKb",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4488(CpuContext ctx) => SetValue(ctx, 71, 178, ValueSource.U8Ref, true);
    // V44_EXPORT_END nid=8C36kDPJiS0

    // V44_EXPORT_BEGIN nid=n8gS5RNyEss
    [SysAbiExport(
        Nid = "n8gS5RNyEss",
        ExportName = "_ZNK3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession18swapSupportedIsSetEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4489(CpuContext ctx) => IsSet(ctx, 71, 178);
    // V44_EXPORT_END nid=n8gS5RNyEss

    // V44_EXPORT_BEGIN nid=Kjnf0JIZhoI
    [SysAbiExport(
        Nid = "Kjnf0JIZhoI",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession19unsetExpirationTimeEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4495(CpuContext ctx) => Unset(ctx, 71, 173);
    // V44_EXPORT_END nid=Kjnf0JIZhoI

    // V44_EXPORT_BEGIN nid=hGRuUBOv+Fw
    [SysAbiExport(
        Nid = "hGRuUBOv+Fw",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession17unsetJoinDisabledEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4497(CpuContext ctx) => Unset(ctx, 71, 174);
    // V44_EXPORT_END nid=hGRuUBOv+Fw

    // V44_EXPORT_BEGIN nid=dnXraQV6Oic
    [SysAbiExport(
        Nid = "dnXraQV6Oic",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession18unsetMaxSpectatorsEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4500(CpuContext ctx) => Unset(ctx, 71, 176);
    // V44_EXPORT_END nid=dnXraQV6Oic

    // V44_EXPORT_BEGIN nid=yLithEbczRA
    [SysAbiExport(
        Nid = "yLithEbczRA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession20unsetNonPsnSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4501(CpuContext ctx) => Unset(ctx, 71, 177);
    // V44_EXPORT_END nid=yLithEbczRA

    // V44_EXPORT_BEGIN nid=PMcRoN6u774
    [SysAbiExport(
        Nid = "PMcRoN6u774",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSession18unsetSwapSupportedEv",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4502(CpuContext ctx) => Unset(ctx, 71, 178);
    // V44_EXPORT_END nid=PMcRoN6u774

    // V44_EXPORT_BEGIN nid=+hBOLtYWNJo
    [SysAbiExport(
        Nid = "+hBOLtYWNJo",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSessionD2Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4503(CpuContext ctx) => Destruct(ctx, 71);
    // V44_EXPORT_END nid=+hBOLtYWNJo

    // V44_EXPORT_BEGIN nid=nwEAY-adORA
    [SysAbiExport(
        Nid = "nwEAY-adORA",
        ExportName = "_ZN3sce2Np9CppWebApi14SessionManager2V120RequestPlayerSessionD1Ev",
        Target = Generation.Gen5,
        LibraryName = "libSceNpCppWebApi")]
    public static int V44Api4504(CpuContext ctx) => Destruct(ctx, 71);
    // V44_EXPORT_END nid=nwEAY-adORA

}
