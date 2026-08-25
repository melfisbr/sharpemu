// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Buffers.Binary;
using System.Numerics;
using System.Runtime.CompilerServices;
using SharpEmu.HLE;

namespace SharpEmu.Libs.LibcCompat;

public static class RuntimeCompilerV45Exports
{
    // V45: deterministic compiler-rt/libatomic subset. This file intentionally
    // excludes C++ exception/RTTI, long-double/x87 and Dinkum _Atomic_* APIs whose
    // exact platform ABI is not established by the supplied V45 evidence.
    private static readonly ConditionalWeakTable<object, object> _atomicGates = new();

    private static int Ok => (int)OrbisGen2Result.ORBIS_GEN2_OK;
    private static int Invalid => (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
    private static int Fault => (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;

    private enum BuiltinKind
    {
        B0001, // __adddf3
        B0002, // __addsf3
        B0003, // __ashlti3
        B0004, // __ashrti3
        B0005, // __atomic_compare_exchange
        B0006, // __atomic_exchange
        B0007, // __atomic_is_lock_free
        B0008, // __atomic_load
        B0009, // __atomic_store
        B0010, // __clzti2
        B0011, // __cmpdi2
        B0012, // __cmpti2
        B0013, // __ctzti2
        B0014, // __divdf3
        B0015, // __divmoddi4
        B0016, // __divmodsi4
        B0017, // __divsf3
        B0018, // __divsi3
        B0019, // __divti3
        B0020, // __eqdf2
        B0021, // __eqsf2
        B0022, // __extendsfdf2
        B0023, // __ffsdi2
        B0024, // __ffsti2
        B0025, // __floatsidf
        B0026, // __floatsisf
        B0027, // __floattidf
        B0028, // __floattisf
        B0029, // __floatunsidf
        B0030, // __floatunsisf
        B0031, // __floatuntidf
        B0032, // __floatuntisf
        B0033, // __gedf2
        B0034, // __gesf2
        B0035, // __gtdf2
        B0036, // __gtsf2
        B0037, // __isfinite
        B0038, // __isfinitef
        B0039, // __isinf
        B0040, // __isinff
        B0041, // __isnan
        B0042, // __isnanf
        B0043, // __isnormal
        B0044, // __isnormalf
        B0045, // __ledf2
        B0046, // __lesf2
        B0047, // __lshrti3
        B0048, // __ltdf2
        B0049, // __ltsf2
        B0050, // __modsi3
        B0051, // __modti3
        B0052, // __muldf3
        B0053, // __mulodi4
        B0054, // __mulosi4
        B0055, // __mulsf3
        B0056, // __multi3
        B0057, // __nedf2
        B0058, // __negdf2
        B0059, // __negdi2
        B0060, // __negsf2
        B0061, // __negti2
        B0062, // __nesf2
        B0063, // __parityti2
        B0064, // __popcountti2
        B0065, // __powidf2
        B0066, // __powisf2
        B0067, // __signbit
        B0068, // __signbitf
        B0069, // __subdf3
        B0070, // __subsf3
        B0071, // __truncdfsf2
        B0072, // __ucmpdi2
        B0073, // __ucmpti2
        B0074, // __udivmoddi4
        B0075, // __udivmodsi4
        B0076, // __udivmodti4
        B0077, // __udivsi3
        B0078, // __udivti3
        B0079, // __umodsi3
        B0080, // __umodti3
        B0081, // __unorddf2
        B0082, // __unordsf2
    }

    private static float ReadF32(CpuContext ctx, int index)
    {
        ctx.GetXmmRegister(index, out var low, out _);
        return BitConverter.UInt32BitsToSingle(unchecked((uint)low));
    }

    private static double ReadF64(CpuContext ctx, int index)
    {
        ctx.GetXmmRegister(index, out var low, out _);
        return BitConverter.UInt64BitsToDouble(low);
    }

    private static void WriteF32(CpuContext ctx, float value) =>
        ctx.SetXmmRegister(0, BitConverter.SingleToUInt32Bits(value), 0);

    private static void WriteF64(CpuContext ctx, double value) =>
        ctx.SetXmmRegister(0, BitConverter.DoubleToUInt64Bits(value), 0);

    private static Int128 ReadI128(ulong low, ulong high) =>
        unchecked((Int128)(((UInt128)high << 64) | low));

    private static UInt128 ReadU128(ulong low, ulong high) =>
        ((UInt128)high << 64) | low;

    private static Int128 ArgI128A(CpuContext ctx) =>
        ReadI128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);

    private static Int128 ArgI128B(CpuContext ctx) =>
        ReadI128(ctx[CpuRegister.Rdx], ctx[CpuRegister.Rcx]);

    private static UInt128 ArgU128A(CpuContext ctx) =>
        ReadU128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);

    private static UInt128 ArgU128B(CpuContext ctx) =>
        ReadU128(ctx[CpuRegister.Rdx], ctx[CpuRegister.Rcx]);

    private static void WriteI128(CpuContext ctx, Int128 value)
    {
        var bits = unchecked((UInt128)value);
        ctx[CpuRegister.Rax] = unchecked((ulong)bits);
        ctx[CpuRegister.Rdx] = unchecked((ulong)(bits >> 64));
    }

    private static void WriteU128(CpuContext ctx, UInt128 value)
    {
        ctx[CpuRegister.Rax] = unchecked((ulong)value);
        ctx[CpuRegister.Rdx] = unchecked((ulong)(value >> 64));
    }

    private static bool TryWriteI32(CpuContext ctx, ulong address, int value)
    {
        if (address == 0)
            return false;
        Span<byte> bytes = stackalloc byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(bytes, value);
        return ctx.Memory.TryWrite(address, bytes);
    }

    private static bool TryWriteI64(CpuContext ctx, ulong address, long value)
    {
        if (address == 0)
            return false;
        Span<byte> bytes = stackalloc byte[8];
        BinaryPrimitives.WriteInt64LittleEndian(bytes, value);
        return ctx.Memory.TryWrite(address, bytes);
    }

    private static bool TryWriteU32(CpuContext ctx, ulong address, uint value)
    {
        if (address == 0)
            return false;
        Span<byte> bytes = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes, value);
        return ctx.Memory.TryWrite(address, bytes);
    }

    private static bool TryWriteU64(CpuContext ctx, ulong address, ulong value)
    {
        if (address == 0)
            return false;
        Span<byte> bytes = stackalloc byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(bytes, value);
        return ctx.Memory.TryWrite(address, bytes);
    }

    private static bool TryWriteU128(CpuContext ctx, ulong address, UInt128 value)
    {
        if (address == 0)
            return false;
        Span<byte> bytes = stackalloc byte[16];
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[..8], unchecked((ulong)value));
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[8..], unchecked((ulong)(value >> 64)));
        return ctx.Memory.TryWrite(address, bytes);
    }

    private static int LeadingZeroCount(UInt128 value)
    {
        var high = unchecked((ulong)(value >> 64));
        return high != 0
            ? BitOperations.LeadingZeroCount(high)
            : 64 + BitOperations.LeadingZeroCount(unchecked((ulong)value));
    }

    private static int TrailingZeroCount(UInt128 value)
    {
        var low = unchecked((ulong)value);
        return low != 0
            ? BitOperations.TrailingZeroCount(low)
            : 64 + BitOperations.TrailingZeroCount(unchecked((ulong)(value >> 64)));
    }

    private static int PopCount(UInt128 value) =>
        BitOperations.PopCount(unchecked((ulong)value)) +
        BitOperations.PopCount(unchecked((ulong)(value >> 64)));

    private static long CompareSigned(long a, long b) => a < b ? 0L : a > b ? 2L : 1L;
    private static long CompareUnsigned(ulong a, ulong b) => a < b ? 0L : a > b ? 2L : 1L;
    private static long CompareSigned128(Int128 a, Int128 b) => a < b ? 0L : a > b ? 2L : 1L;
    private static long CompareUnsigned128(UInt128 a, UInt128 b) => a < b ? 0L : a > b ? 2L : 1L;

    private static long CompareLe(double a, double b) =>
        double.IsNaN(a) || double.IsNaN(b) ? 1L : a < b ? -1L : a > b ? 1L : 0L;

    private static long CompareLe(float a, float b) =>
        float.IsNaN(a) || float.IsNaN(b) ? 1L : a < b ? -1L : a > b ? 1L : 0L;

    private static long CompareGe(double a, double b) =>
        double.IsNaN(a) || double.IsNaN(b) ? -1L : a < b ? -1L : a > b ? 1L : 0L;

    private static long CompareGe(float a, float b) =>
        float.IsNaN(a) || float.IsNaN(b) ? -1L : a < b ? -1L : a > b ? 1L : 0L;

    private static double PowInteger(double value, int exponent)
    {
        if (exponent == 0)
            return 1.0;

        var negative = exponent < 0;
        uint power = negative
            ? unchecked((uint)(-(long)exponent))
            : unchecked((uint)exponent);
        var result = 1.0;
        var factor = value;
        while (power != 0)
        {
            if ((power & 1U) != 0)
                result *= factor;
            factor *= factor;
            power >>= 1;
        }
        return negative ? 1.0 / result : result;
    }

    private static float PowInteger(float value, int exponent)
    {
        if (exponent == 0)
            return 1.0f;

        var negative = exponent < 0;
        uint power = negative
            ? unchecked((uint)(-(long)exponent))
            : unchecked((uint)exponent);
        var result = 1.0f;
        var factor = value;
        while (power != 0)
        {
            if ((power & 1U) != 0)
                result *= factor;
            factor *= factor;
            power >>= 1;
        }
        return negative ? 1.0f / result : result;
    }

    private static bool IsNormal(double value)
    {
        var bits = BitConverter.DoubleToUInt64Bits(value) & 0x7FFF_FFFF_FFFF_FFFFUL;
        return bits >= 0x0010_0000_0000_0000UL && bits < 0x7FF0_0000_0000_0000UL;
    }

    private static bool IsNormal(float value)
    {
        var bits = BitConverter.SingleToUInt32Bits(value) & 0x7FFF_FFFFU;
        return bits >= 0x0080_0000U && bits < 0x7F80_0000U;
    }

    private static bool TryAtomicSize(CpuContext ctx, out int size)
    {
        var raw = ctx[CpuRegister.Rdi];
        if (raw == 0 || raw > 1_048_576UL)
        {
            size = 0;
            return false;
        }

        size = unchecked((int)raw);
        return true;
    }

    private static object AtomicGate(CpuContext ctx) =>
        _atomicGates.GetValue(ctx.Memory, static _ => new object());

    private static int AtomicLoad(CpuContext ctx)
    {
        if (!TryAtomicSize(ctx, out var size))
            return Invalid;
        var source = ctx[CpuRegister.Rsi];
        var destination = ctx[CpuRegister.Rdx];
        if (source == 0 || destination == 0)
            return Invalid;

        var bytes = new byte[size];
        lock (AtomicGate(ctx))
        {
            if (!ctx.Memory.TryRead(source, bytes) || !ctx.Memory.TryWrite(destination, bytes))
                return Fault;
        }
        return Ok;
    }

    private static int AtomicStore(CpuContext ctx)
    {
        if (!TryAtomicSize(ctx, out var size))
            return Invalid;
        var destination = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        if (source == 0 || destination == 0)
            return Invalid;

        var bytes = new byte[size];
        lock (AtomicGate(ctx))
        {
            if (!ctx.Memory.TryRead(source, bytes) || !ctx.Memory.TryWrite(destination, bytes))
                return Fault;
        }
        return Ok;
    }

    private static int AtomicExchange(CpuContext ctx)
    {
        if (!TryAtomicSize(ctx, out var size))
            return Invalid;
        var target = ctx[CpuRegister.Rsi];
        var valueAddress = ctx[CpuRegister.Rdx];
        var resultAddress = ctx[CpuRegister.Rcx];
        if (target == 0 || valueAddress == 0 || resultAddress == 0)
            return Invalid;

        var current = new byte[size];
        var replacement = new byte[size];
        lock (AtomicGate(ctx))
        {
            if (!ctx.Memory.TryRead(target, current) ||
                !ctx.Memory.TryRead(valueAddress, replacement) ||
                !ctx.Memory.TryWrite(target, replacement) ||
                !ctx.Memory.TryWrite(resultAddress, current))
                return Fault;
        }
        return Ok;
    }

    private static int AtomicCompareExchange(CpuContext ctx)
    {
        if (!TryAtomicSize(ctx, out var size))
            return Invalid;
        var target = ctx[CpuRegister.Rsi];
        var expectedAddress = ctx[CpuRegister.Rdx];
        var desiredAddress = ctx[CpuRegister.Rcx];
        if (target == 0 || expectedAddress == 0 || desiredAddress == 0)
            return Invalid;

        var current = new byte[size];
        var expected = new byte[size];
        var desired = new byte[size];
        var exchanged = false;
        lock (AtomicGate(ctx))
        {
            if (!ctx.Memory.TryRead(target, current) ||
                !ctx.Memory.TryRead(expectedAddress, expected) ||
                !ctx.Memory.TryRead(desiredAddress, desired))
                return Fault;

            if (current.AsSpan().SequenceEqual(expected))
            {
                if (!ctx.Memory.TryWrite(target, desired))
                    return Fault;
                exchanged = true;
            }
            else if (!ctx.Memory.TryWrite(expectedAddress, current))
            {
                return Fault;
            }
        }

        ctx[CpuRegister.Rax] = exchanged ? 1UL : 0UL;
        return Ok;
    }

    private static int ExecuteBuiltin(CpuContext ctx, BuiltinKind kind)
    {
        switch (kind)
        {
            case BuiltinKind.B0001: // __adddf3
                {
                    WriteF64(ctx, ReadF64(ctx, 0) + ReadF64(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0002: // __addsf3
                {
                    WriteF32(ctx, ReadF32(ctx, 0) + ReadF32(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0003: // __ashlti3
                {
                    var value = ArgU128A(ctx);
                    var shift = unchecked((int)(ctx[CpuRegister.Rdx] & 127UL));
                    WriteU128(ctx, value << shift);
                    return Ok;
                }
            case BuiltinKind.B0004: // __ashrti3
                {
                    var value = ArgI128A(ctx);
                    var shift = unchecked((int)(ctx[CpuRegister.Rdx] & 127UL));
                    WriteI128(ctx, value >> shift);
                    return Ok;
                }
            case BuiltinKind.B0005: // __atomic_compare_exchange
                {
                    return AtomicCompareExchange(ctx);
                }
            case BuiltinKind.B0006: // __atomic_exchange
                {
                    return AtomicExchange(ctx);
                }
            case BuiltinKind.B0007: // __atomic_is_lock_free
                {
                    // V45's generic atomic path is intentionally lock-backed, so reporting
                    // "not lock-free" is the truthful capability result for this HLE backend.
                    ctx[CpuRegister.Rax] = 0;
                    return Ok;
                }
            case BuiltinKind.B0008: // __atomic_load
                {
                    return AtomicLoad(ctx);
                }
            case BuiltinKind.B0009: // __atomic_store
                {
                    return AtomicStore(ctx);
                }
            case BuiltinKind.B0010: // __clzti2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)LeadingZeroCount(ArgU128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0011: // __cmpdi2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)CompareSigned(unchecked((long)ctx[CpuRegister.Rdi]), unchecked((long)ctx[CpuRegister.Rsi])));
                    return Ok;
                }
            case BuiltinKind.B0012: // __cmpti2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)CompareSigned128(ArgI128A(ctx), ArgI128B(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0013: // __ctzti2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)TrailingZeroCount(ArgU128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0014: // __divdf3
                {
                    WriteF64(ctx, ReadF64(ctx, 0) / ReadF64(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0015: // __divmoddi4
                {
                    var a = unchecked((long)ctx[CpuRegister.Rdi]);
                    var b = unchecked((long)ctx[CpuRegister.Rsi]);
                    if (b == 0 || (a == long.MinValue && b == -1))
                        return Invalid;
                    var q = a / b;
                    var rem = a % b;
                    if (!TryWriteI64(ctx, ctx[CpuRegister.Rdx], rem))
                        return Fault;
                    ctx[CpuRegister.Rax] = unchecked((ulong)q);
                    return Ok;
                }
            case BuiltinKind.B0016: // __divmodsi4
                {
                    var a = unchecked((int)ctx[CpuRegister.Rdi]);
                    var b = unchecked((int)ctx[CpuRegister.Rsi]);
                    if (b == 0 || (a == int.MinValue && b == -1))
                        return Invalid;
                    var q = a / b;
                    var rem = a % b;
                    if (!TryWriteI32(ctx, ctx[CpuRegister.Rdx], rem))
                        return Fault;
                    ctx[CpuRegister.Rax] = unchecked((uint)q);
                    return Ok;
                }
            case BuiltinKind.B0017: // __divsf3
                {
                    WriteF32(ctx, ReadF32(ctx, 0) / ReadF32(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0018: // __divsi3
                {
                    var a = unchecked((int)ctx[CpuRegister.Rdi]);
                    var b = unchecked((int)ctx[CpuRegister.Rsi]);
                    if (b == 0 || (a == int.MinValue && b == -1))
                        return Invalid;
                    ctx[CpuRegister.Rax] = unchecked((uint)(a / b));
                    return Ok;
                }
            case BuiltinKind.B0019: // __divti3
                {
                    var a = ArgI128A(ctx);
                    var b = ArgI128B(ctx);
                    if (b == 0 || (a == Int128.MinValue && b == -1))
                        return Invalid;
                    WriteI128(ctx, a / b);
                    return Ok;
                }
            case BuiltinKind.B0020: // __eqdf2
                {
                    var a = ReadF64(ctx, 0);
                    var b = ReadF64(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)((double.IsNaN(a) || double.IsNaN(b) || a != b) ? 1L : 0L));
                    return Ok;
                }
            case BuiltinKind.B0021: // __eqsf2
                {
                    var a = ReadF32(ctx, 0);
                    var b = ReadF32(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)((float.IsNaN(a) || float.IsNaN(b) || a != b) ? 1L : 0L));
                    return Ok;
                }
            case BuiltinKind.B0022: // __extendsfdf2
                {
                    WriteF64(ctx, ReadF32(ctx, 0));
                    return Ok;
                }
            case BuiltinKind.B0023: // __ffsdi2
                {
                    var value = ctx[CpuRegister.Rdi];
                    ctx[CpuRegister.Rax] = value == 0 ? 0UL : unchecked((ulong)(BitOperations.TrailingZeroCount(value) + 1));
                    return Ok;
                }
            case BuiltinKind.B0024: // __ffsti2
                {
                    var value = ArgU128A(ctx);
                    ctx[CpuRegister.Rax] = value == 0 ? 0UL : unchecked((ulong)(TrailingZeroCount(value) + 1));
                    return Ok;
                }
            case BuiltinKind.B0025: // __floatsidf
                {
                    WriteF64(ctx, unchecked((int)ctx[CpuRegister.Rdi]));
                    return Ok;
                }
            case BuiltinKind.B0026: // __floatsisf
                {
                    WriteF32(ctx, unchecked((int)ctx[CpuRegister.Rdi]));
                    return Ok;
                }
            case BuiltinKind.B0027: // __floattidf
                {
                    WriteF64(ctx, unchecked((double)ArgI128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0028: // __floattisf
                {
                    WriteF32(ctx, unchecked((float)ArgI128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0029: // __floatunsidf
                {
                    WriteF64(ctx, unchecked((uint)ctx[CpuRegister.Rdi]));
                    return Ok;
                }
            case BuiltinKind.B0030: // __floatunsisf
                {
                    WriteF32(ctx, unchecked((uint)ctx[CpuRegister.Rdi]));
                    return Ok;
                }
            case BuiltinKind.B0031: // __floatuntidf
                {
                    WriteF64(ctx, unchecked((double)ArgU128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0032: // __floatuntisf
                {
                    WriteF32(ctx, unchecked((float)ArgU128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0033: // __gedf2
                {
                    var a = ReadF64(ctx, 0);
                    var b = ReadF64(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareGe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0034: // __gesf2
                {
                    var a = ReadF32(ctx, 0);
                    var b = ReadF32(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareGe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0035: // __gtdf2
                {
                    var a = ReadF64(ctx, 0);
                    var b = ReadF64(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareGe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0036: // __gtsf2
                {
                    var a = ReadF32(ctx, 0);
                    var b = ReadF32(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareGe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0037: // __isfinite
                {
                    var value = ReadF64(ctx, 0);
                    ctx[CpuRegister.Rax] = double.IsFinite(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0038: // __isfinitef
                {
                    var value = ReadF32(ctx, 0);
                    ctx[CpuRegister.Rax] = float.IsFinite(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0039: // __isinf
                {
                    var value = ReadF64(ctx, 0);
                    ctx[CpuRegister.Rax] = double.IsInfinity(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0040: // __isinff
                {
                    var value = ReadF32(ctx, 0);
                    ctx[CpuRegister.Rax] = float.IsInfinity(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0041: // __isnan
                {
                    var value = ReadF64(ctx, 0);
                    ctx[CpuRegister.Rax] = double.IsNaN(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0042: // __isnanf
                {
                    var value = ReadF32(ctx, 0);
                    ctx[CpuRegister.Rax] = float.IsNaN(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0043: // __isnormal
                {
                    var value = ReadF64(ctx, 0);
                    ctx[CpuRegister.Rax] = IsNormal(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0044: // __isnormalf
                {
                    var value = ReadF32(ctx, 0);
                    ctx[CpuRegister.Rax] = IsNormal(value) ? 1UL : 0UL;
                    return Ok;
                }
            case BuiltinKind.B0045: // __ledf2
                {
                    var a = ReadF64(ctx, 0);
                    var b = ReadF64(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareLe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0046: // __lesf2
                {
                    var a = ReadF32(ctx, 0);
                    var b = ReadF32(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareLe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0047: // __lshrti3
                {
                    var value = ArgU128A(ctx);
                    var shift = unchecked((int)(ctx[CpuRegister.Rdx] & 127UL));
                    WriteU128(ctx, value >> shift);
                    return Ok;
                }
            case BuiltinKind.B0048: // __ltdf2
                {
                    var a = ReadF64(ctx, 0);
                    var b = ReadF64(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareLe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0049: // __ltsf2
                {
                    var a = ReadF32(ctx, 0);
                    var b = ReadF32(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)(CompareLe(a, b)));
                    return Ok;
                }
            case BuiltinKind.B0050: // __modsi3
                {
                    var a = unchecked((int)ctx[CpuRegister.Rdi]);
                    var b = unchecked((int)ctx[CpuRegister.Rsi]);
                    if (b == 0 || (a == int.MinValue && b == -1))
                        return Invalid;
                    ctx[CpuRegister.Rax] = unchecked((uint)(a % b));
                    return Ok;
                }
            case BuiltinKind.B0051: // __modti3
                {
                    var a = ArgI128A(ctx);
                    var b = ArgI128B(ctx);
                    if (b == 0 || (a == Int128.MinValue && b == -1))
                        return Invalid;
                    WriteI128(ctx, a % b);
                    return Ok;
                }
            case BuiltinKind.B0052: // __muldf3
                {
                    WriteF64(ctx, ReadF64(ctx, 0) * ReadF64(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0053: // __mulodi4
                {
                    var a = unchecked((long)ctx[CpuRegister.Rdi]);
                    var b = unchecked((long)ctx[CpuRegister.Rsi]);
                    var product = (Int128)a * b;
                    if (!TryWriteI32(ctx, ctx[CpuRegister.Rdx], product < long.MinValue || product > long.MaxValue ? 1 : 0))
                        return Fault;
                    ctx[CpuRegister.Rax] = unchecked((ulong)(long)product);
                    return Ok;
                }
            case BuiltinKind.B0054: // __mulosi4
                {
                    var a = unchecked((int)ctx[CpuRegister.Rdi]);
                    var b = unchecked((int)ctx[CpuRegister.Rsi]);
                    var product = (long)a * b;
                    if (!TryWriteI32(ctx, ctx[CpuRegister.Rdx], product < int.MinValue || product > int.MaxValue ? 1 : 0))
                        return Fault;
                    ctx[CpuRegister.Rax] = unchecked((uint)(int)product);
                    return Ok;
                }
            case BuiltinKind.B0055: // __mulsf3
                {
                    WriteF32(ctx, ReadF32(ctx, 0) * ReadF32(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0056: // __multi3
                {
                    WriteI128(ctx, unchecked(ArgI128A(ctx) * ArgI128B(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0057: // __nedf2
                {
                    var a = ReadF64(ctx, 0);
                    var b = ReadF64(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)((double.IsNaN(a) || double.IsNaN(b) || a != b) ? 1L : 0L));
                    return Ok;
                }
            case BuiltinKind.B0058: // __negdf2
                {
                    WriteF64(ctx, -ReadF64(ctx, 0));
                    return Ok;
                }
            case BuiltinKind.B0059: // __negdi2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)(-unchecked((long)ctx[CpuRegister.Rdi])));
                    return Ok;
                }
            case BuiltinKind.B0060: // __negsf2
                {
                    WriteF32(ctx, -ReadF32(ctx, 0));
                    return Ok;
                }
            case BuiltinKind.B0061: // __negti2
                {
                    WriteI128(ctx, unchecked(-ArgI128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0062: // __nesf2
                {
                    var a = ReadF32(ctx, 0);
                    var b = ReadF32(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)((float.IsNaN(a) || float.IsNaN(b) || a != b) ? 1L : 0L));
                    return Ok;
                }
            case BuiltinKind.B0063: // __parityti2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)(PopCount(ArgU128A(ctx)) & 1));
                    return Ok;
                }
            case BuiltinKind.B0064: // __popcountti2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)PopCount(ArgU128A(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0065: // __powidf2
                {
                    WriteF64(ctx, PowInteger(ReadF64(ctx, 0), unchecked((int)ctx[CpuRegister.Rdi])));
                    return Ok;
                }
            case BuiltinKind.B0066: // __powisf2
                {
                    WriteF32(ctx, PowInteger(ReadF32(ctx, 0), unchecked((int)ctx[CpuRegister.Rdi])));
                    return Ok;
                }
            case BuiltinKind.B0067: // __signbit
                {
                    ctx[CpuRegister.Rax] = (BitConverter.DoubleToUInt64Bits(ReadF64(ctx, 0)) >> 63) & 1UL;
                    return Ok;
                }
            case BuiltinKind.B0068: // __signbitf
                {
                    ctx[CpuRegister.Rax] = (BitConverter.SingleToUInt32Bits(ReadF32(ctx, 0)) >> 31) & 1U;
                    return Ok;
                }
            case BuiltinKind.B0069: // __subdf3
                {
                    WriteF64(ctx, ReadF64(ctx, 0) - ReadF64(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0070: // __subsf3
                {
                    WriteF32(ctx, ReadF32(ctx, 0) - ReadF32(ctx, 1));
                    return Ok;
                }
            case BuiltinKind.B0071: // __truncdfsf2
                {
                    WriteF32(ctx, unchecked((float)ReadF64(ctx, 0)));
                    return Ok;
                }
            case BuiltinKind.B0072: // __ucmpdi2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)CompareUnsigned(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
                    return Ok;
                }
            case BuiltinKind.B0073: // __ucmpti2
                {
                    ctx[CpuRegister.Rax] = unchecked((ulong)CompareUnsigned128(ArgU128A(ctx), ArgU128B(ctx)));
                    return Ok;
                }
            case BuiltinKind.B0074: // __udivmoddi4
                {
                    var a = ctx[CpuRegister.Rdi];
                    var b = ctx[CpuRegister.Rsi];
                    if (b == 0)
                        return Invalid;
                    var q = a / b;
                    var rem = a % b;
                    if (!TryWriteU64(ctx, ctx[CpuRegister.Rdx], rem))
                        return Fault;
                    ctx[CpuRegister.Rax] = q;
                    return Ok;
                }
            case BuiltinKind.B0075: // __udivmodsi4
                {
                    var a = unchecked((uint)ctx[CpuRegister.Rdi]);
                    var b = unchecked((uint)ctx[CpuRegister.Rsi]);
                    if (b == 0)
                        return Invalid;
                    var q = a / b;
                    var rem = a % b;
                    if (!TryWriteU32(ctx, ctx[CpuRegister.Rdx], rem))
                        return Fault;
                    ctx[CpuRegister.Rax] = q;
                    return Ok;
                }
            case BuiltinKind.B0076: // __udivmodti4
                {
                    var a = ArgU128A(ctx);
                    var b = ArgU128B(ctx);
                    if (b == 0)
                        return Invalid;
                    var q = a / b;
                    var rem = a % b;
                    if (!TryWriteU128(ctx, ctx[CpuRegister.R8], rem))
                        return Fault;
                    WriteU128(ctx, q);
                    return Ok;
                }
            case BuiltinKind.B0077: // __udivsi3
                {
                    var a = unchecked((uint)ctx[CpuRegister.Rdi]);
                    var b = unchecked((uint)ctx[CpuRegister.Rsi]);
                    if (b == 0)
                        return Invalid;
                    ctx[CpuRegister.Rax] = a / b;
                    return Ok;
                }
            case BuiltinKind.B0078: // __udivti3
                {
                    var a = ArgU128A(ctx);
                    var b = ArgU128B(ctx);
                    if (b == 0)
                        return Invalid;
                    WriteU128(ctx, a / b);
                    return Ok;
                }
            case BuiltinKind.B0079: // __umodsi3
                {
                    var a = unchecked((uint)ctx[CpuRegister.Rdi]);
                    var b = unchecked((uint)ctx[CpuRegister.Rsi]);
                    if (b == 0)
                        return Invalid;
                    ctx[CpuRegister.Rax] = a % b;
                    return Ok;
                }
            case BuiltinKind.B0080: // __umodti3
                {
                    var a = ArgU128A(ctx);
                    var b = ArgU128B(ctx);
                    if (b == 0)
                        return Invalid;
                    WriteU128(ctx, a % b);
                    return Ok;
                }
            case BuiltinKind.B0081: // __unorddf2
                {
                    var a = ReadF64(ctx, 0);
                    var b = ReadF64(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)((double.IsNaN(a) || double.IsNaN(b)) ? 1L : 0L));
                    return Ok;
                }
            case BuiltinKind.B0082: // __unordsf2
                {
                    var a = ReadF32(ctx, 0);
                    var b = ReadF32(ctx, 1);
                    ctx[CpuRegister.Rax] = unchecked((ulong)((float.IsNaN(a) || float.IsNaN(b)) ? 1L : 0L));
                    return Ok;
                }
            default:
                return Invalid;
        }
    }





    // V45_EXPORT_BEGIN nid=ClfCoK1Zeb4
    [SysAbiExport(
        Nid = "ClfCoK1Zeb4",
        ExportName = "__atomic_compare_exchange",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0005(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0005);
    // V45_EXPORT_END nid=ClfCoK1Zeb4

    // V45_EXPORT_BEGIN nid=5i8mTQeo9hs
    [SysAbiExport(
        Nid = "5i8mTQeo9hs",
        ExportName = "__atomic_exchange",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0006(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0006);
    // V45_EXPORT_END nid=5i8mTQeo9hs

    // V45_EXPORT_BEGIN nid=JZWEhLSIMoQ
    [SysAbiExport(
        Nid = "JZWEhLSIMoQ",
        ExportName = "__atomic_is_lock_free",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0007(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0007);
    // V45_EXPORT_END nid=JZWEhLSIMoQ

    // V45_EXPORT_BEGIN nid=+iy+BecyFVw
    [SysAbiExport(
        Nid = "+iy+BecyFVw",
        ExportName = "__atomic_load",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0008(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0008);
    // V45_EXPORT_END nid=+iy+BecyFVw

    // V45_EXPORT_BEGIN nid=sV6ry-Fd-TM
    [SysAbiExport(
        Nid = "sV6ry-Fd-TM",
        ExportName = "__atomic_store",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0009(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0009);
    // V45_EXPORT_END nid=sV6ry-Fd-TM






    // V45_EXPORT_BEGIN nid=1rs4-h7Fq9U
    [SysAbiExport(
        Nid = "1rs4-h7Fq9U",
        ExportName = "__divmoddi4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0015(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0015);
    // V45_EXPORT_END nid=1rs4-h7Fq9U

    // V45_EXPORT_BEGIN nid=rtBENmz8Iwc
    [SysAbiExport(
        Nid = "rtBENmz8Iwc",
        ExportName = "__divmodsi4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0016(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0016);
    // V45_EXPORT_END nid=rtBENmz8Iwc


    // V45_EXPORT_BEGIN nid=zdJ3GXAcI9M
    [SysAbiExport(
        Nid = "zdJ3GXAcI9M",
        ExportName = "__divsi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0018(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0018);
    // V45_EXPORT_END nid=zdJ3GXAcI9M

    // V45_EXPORT_BEGIN nid=XU4yLKvcDh0
    [SysAbiExport(
        Nid = "XU4yLKvcDh0",
        ExportName = "__divti3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0019(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0019);
    // V45_EXPORT_END nid=XU4yLKvcDh0































    // V45_EXPORT_BEGIN nid=k0vARyJi9oU
    [SysAbiExport(
        Nid = "k0vARyJi9oU",
        ExportName = "__modsi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0050(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0050);
    // V45_EXPORT_END nid=k0vARyJi9oU

    // V45_EXPORT_BEGIN nid=J8JRHcUKWP4
    [SysAbiExport(
        Nid = "J8JRHcUKWP4",
        ExportName = "__modti3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0051(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0051);
    // V45_EXPORT_END nid=J8JRHcUKWP4























    // V45_EXPORT_BEGIN nid=EWWEBA+Ldw8
    [SysAbiExport(
        Nid = "EWWEBA+Ldw8",
        ExportName = "__udivmoddi4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0074(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0074);
    // V45_EXPORT_END nid=EWWEBA+Ldw8

    // V45_EXPORT_BEGIN nid=PPdIvXwUQwA
    [SysAbiExport(
        Nid = "PPdIvXwUQwA",
        ExportName = "__udivmodsi4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0075(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0075);
    // V45_EXPORT_END nid=PPdIvXwUQwA

    // V45_EXPORT_BEGIN nid=lcNk3Ar5rUQ
    [SysAbiExport(
        Nid = "lcNk3Ar5rUQ",
        ExportName = "__udivmodti4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0076(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0076);
    // V45_EXPORT_END nid=lcNk3Ar5rUQ

    // V45_EXPORT_BEGIN nid=PxP1PFdu9OQ
    [SysAbiExport(
        Nid = "PxP1PFdu9OQ",
        ExportName = "__udivsi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0077(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0077);
    // V45_EXPORT_END nid=PxP1PFdu9OQ

    // V45_EXPORT_BEGIN nid=802pFCwC9w0
    [SysAbiExport(
        Nid = "802pFCwC9w0",
        ExportName = "__udivti3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0078(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0078);
    // V45_EXPORT_END nid=802pFCwC9w0

    // V45_EXPORT_BEGIN nid=p4vYrlsVpDE
    [SysAbiExport(
        Nid = "p4vYrlsVpDE",
        ExportName = "__umodsi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0079(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0079);
    // V45_EXPORT_END nid=p4vYrlsVpDE

    // V45_EXPORT_BEGIN nid=ELSr5qm4K1M
    [SysAbiExport(
        Nid = "ELSr5qm4K1M",
        ExportName = "__umodti3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceLibcInternal")]
    public static int V45Runtime0080(CpuContext ctx) =>
        ExecuteBuiltin(ctx, BuiltinKind.B0080);
    // V45_EXPORT_END nid=ELSr5qm4K1M



}
