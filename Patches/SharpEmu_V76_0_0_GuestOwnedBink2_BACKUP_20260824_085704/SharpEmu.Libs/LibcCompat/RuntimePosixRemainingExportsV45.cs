// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers;
using System.Buffers.Binary;
using System.Numerics;
using SharpEmu.HLE;

namespace SharpEmu.Libs.LibcCompat;

/// <summary>
/// V45 deterministic runtime/POSIX/compiler-rt compatibility exports.
///
/// Scope is intentionally restricted to ABI-stable scalar compiler helpers and
/// local libc/POSIX operations. C++ object layouts, RTTI data objects, exception
/// machinery, networking and proprietary service semantics are not guessed here.
/// </summary>
public static class RuntimePosixRemainingExportsV45
{
    // V45: deterministic runtime/POSIX/compiler-rt functional subset.
    private const int MaxCStringScan = 16 * 1024 * 1024;
    private const int CopyChunk = 64 * 1024;
    private const ulong Rand48Mask = (1UL << 48) - 1;
    private const ulong Rand48Multiplier = 0x5DEECE66DUL;
    private const ulong Rand48Addend = 0xBUL;
    private static readonly object Rand48Gate = new();
    private static ulong _rand48State = 0x1234ABCD330EUL;

    private static readonly BigInteger U128Mod = BigInteger.One << 128;
    private static readonly BigInteger U128Mask = U128Mod - BigInteger.One;
    private static readonly BigInteger S128Min = -(BigInteger.One << 127);
    private static readonly BigInteger S128Max = (BigInteger.One << 127) - BigInteger.One;
    private static readonly BigInteger U64Mask = new(ulong.MaxValue);

    private static int Ok => (int)OrbisGen2Result.ORBIS_GEN2_OK;
    private static int MemoryFault => (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;

    private static double GetDouble(CpuContext ctx, int xmm)
    {
        ctx.GetXmmRegister(xmm, out var low, out _);
        return BitConverter.Int64BitsToDouble(unchecked((long)low));
    }

    private static float GetFloat(CpuContext ctx, int xmm)
    {
        ctx.GetXmmRegister(xmm, out var low, out _);
        return BitConverter.Int32BitsToSingle(unchecked((int)(uint)low));
    }

    private static int ReturnDouble(CpuContext ctx, double value)
    {
        ctx.SetXmmRegister(0, unchecked((ulong)BitConverter.DoubleToInt64Bits(value)), 0);
        return Ok;
    }

    private static int ReturnFloat(CpuContext ctx, float value)
    {
        ctx.SetXmmRegister(0, unchecked((uint)BitConverter.SingleToInt32Bits(value)), 0);
        return Ok;
    }

    private static int ReturnInt(CpuContext ctx, int value)
    {
        ctx[CpuRegister.Rax] = unchecked((uint)value);
        return Ok;
    }

    private static int ReturnUInt(CpuContext ctx, uint value)
    {
        ctx[CpuRegister.Rax] = value;
        return Ok;
    }

    private static int ReturnLong(CpuContext ctx, long value)
    {
        ctx[CpuRegister.Rax] = unchecked((ulong)value);
        return Ok;
    }

    private static int ReturnULong(CpuContext ctx, ulong value)
    {
        ctx[CpuRegister.Rax] = value;
        return Ok;
    }

    private static int ReturnPointer(CpuContext ctx, ulong value)
    {
        ctx[CpuRegister.Rax] = value;
        return Ok;
    }

    private static BigInteger U128(ulong lo, ulong hi) =>
        ((BigInteger)hi << 64) | lo;

    private static BigInteger S128(ulong lo, ulong hi)
    {
        var u = U128(lo, hi);
        return (hi & 0x8000_0000_0000_0000UL) != 0 ? u - U128Mod : u;
    }

    private static BigInteger WrapU128(BigInteger value)
    {
        value %= U128Mod;
        if (value.Sign < 0) value += U128Mod;
        return value;
    }

    private static int Return128(CpuContext ctx, BigInteger value)
    {
        var u = WrapU128(value);
        ctx[CpuRegister.Rax] = (ulong)(u & U64Mask);
        ctx[CpuRegister.Rdx] = (ulong)((u >> 64) & U64Mask);
        return Ok;
    }

    private static int LeadingZeros128(ulong lo, ulong hi) =>
        hi != 0 ? BitOperations.LeadingZeroCount(hi) : 64 + BitOperations.LeadingZeroCount(lo);

    private static int TrailingZeros128(ulong lo, ulong hi) =>
        lo != 0 ? BitOperations.TrailingZeroCount(lo) : 64 + BitOperations.TrailingZeroCount(hi);

    private static int PopCount128(ulong lo, ulong hi) =>
        BitOperations.PopCount(lo) + BitOperations.PopCount(hi);

    private static bool TryWriteInt32(CpuContext ctx, ulong address, int value)
    {
        Span<byte> data = stackalloc byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(data, value);
        return ctx.Memory.TryWrite(address, data);
    }

    private static bool TryReadUInt64(CpuContext ctx, ulong address, out ulong value)
    {
        Span<byte> data = stackalloc byte[8];
        if (!ctx.Memory.TryRead(address, data))
        {
            value = 0;
            return false;
        }
        value = BinaryPrimitives.ReadUInt64LittleEndian(data);
        return true;
    }

    private static bool TryWriteUInt64(CpuContext ctx, ulong address, ulong value)
    {
        Span<byte> data = stackalloc byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(data, value);
        return ctx.Memory.TryWrite(address, data);
    }

    private static bool TryWriteDouble(CpuContext ctx, ulong address, double value) =>
        TryWriteUInt64(ctx, address, unchecked((ulong)BitConverter.DoubleToInt64Bits(value)));

    private static bool TryWriteFloat(CpuContext ctx, ulong address, float value)
    {
        Span<byte> data = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(data, unchecked((uint)BitConverter.SingleToInt32Bits(value)));
        return ctx.Memory.TryWrite(address, data);
    }

    private static bool TryReadRand48(CpuContext ctx, ulong address, out ulong state)
    {
        Span<byte> data = stackalloc byte[6];
        if (!ctx.Memory.TryRead(address, data))
        {
            state = 0;
            return false;
        }
        var x0 = BinaryPrimitives.ReadUInt16LittleEndian(data[..2]);
        var x1 = BinaryPrimitives.ReadUInt16LittleEndian(data.Slice(2, 2));
        var x2 = BinaryPrimitives.ReadUInt16LittleEndian(data.Slice(4, 2));
        state = (ulong)x0 | ((ulong)x1 << 16) | ((ulong)x2 << 32);
        return true;
    }

    private static bool TryWriteRand48(CpuContext ctx, ulong address, ulong state)
    {
        Span<byte> data = stackalloc byte[6];
        BinaryPrimitives.WriteUInt16LittleEndian(data[..2], (ushort)state);
        BinaryPrimitives.WriteUInt16LittleEndian(data.Slice(2, 2), (ushort)(state >> 16));
        BinaryPrimitives.WriteUInt16LittleEndian(data.Slice(4, 2), (ushort)(state >> 32));
        return ctx.Memory.TryWrite(address, data);
    }

    private static ulong Next48(ulong state) =>
        unchecked((state * Rand48Multiplier + Rand48Addend) & Rand48Mask);

    private static double StateToUnitDouble(ulong state) =>
        state / 281474976710656.0; // 2^48

    private static double Expm1(double x)
    {
        if (double.IsNaN(x) || double.IsInfinity(x) || Math.Abs(x) >= 1.0e-5)
            return Math.Exp(x) - 1.0;

        // Stable local series near zero.
        var term = x;
        var sum = x;
        for (var n = 2; n <= 12; n++)
        {
            term *= x / n;
            sum += term;
        }
        return sum;
    }

    private static bool TryCStringLength(CpuContext ctx, ulong address, out int length, int cap = MaxCStringScan)
    {
        length = 0;
        if (address == 0) return false;
        for (var i = 0; i < cap; i++)
        {
            if (!ctx.TryReadByte(address + (ulong)i, out var b)) return false;
            if (b == 0)
            {
                length = i;
                return true;
            }
        }
        return false;
    }

    private static bool TryReadCStringBytes(CpuContext ctx, ulong address, out byte[] bytes, int cap = 4096)
    {
        bytes = Array.Empty<byte>();
        if (!TryCStringLength(ctx, address, out var length, cap)) return false;
        bytes = new byte[length];
        return length == 0 || ctx.Memory.TryRead(address, bytes);
    }

    private static bool ContainsByte(byte[] set, byte value)
    {
        for (var i = 0; i < set.Length; i++)
            if (set[i] == value) return true;
        return false;
    }

    private static int EqCompare(double a, double b) =>
        !double.IsNaN(a) && !double.IsNaN(b) && a == b ? 0 : 1;

    private static int EqCompare(float a, float b) =>
        !float.IsNaN(a) && !float.IsNaN(b) && a == b ? 0 : 1;

    private static int GeCompare(double a, double b)
    {
        if (double.IsNaN(a) || double.IsNaN(b)) return -1;
        return a < b ? -1 : a > b ? 1 : 0;
    }

    private static int GeCompare(float a, float b)
    {
        if (float.IsNaN(a) || float.IsNaN(b)) return -1;
        return a < b ? -1 : a > b ? 1 : 0;
    }

    private static int LeCompare(double a, double b)
    {
        if (double.IsNaN(a) || double.IsNaN(b)) return 1;
        return a < b ? -1 : a > b ? 1 : 0;
    }

    private static int LeCompare(float a, float b)
    {
        if (float.IsNaN(a) || float.IsNaN(b)) return 1;
        return a < b ? -1 : a > b ? 1 : 0;
    }

    private static bool IsNormal(double value)
    {
        var bits = unchecked((ulong)BitConverter.DoubleToInt64Bits(value));
        var exp = (bits >> 52) & 0x7FFUL;
        return exp != 0 && exp != 0x7FFUL;
    }

    private static bool IsNormal(float value)
    {
        var bits = unchecked((uint)BitConverter.SingleToInt32Bits(value));
        var exp = (bits >> 23) & 0xFFU;
        return exp != 0 && exp != 0xFFU;
    }

}
