// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers;
using System.Buffers.Binary;
using System.Numerics;
using SharpEmu.HLE;

namespace SharpEmu.Libs.LibcCompat;

/// <summary>
/// V54 current-state-filtered runtime/POSIX/compiler-rt compatibility exports.
///
/// Scope is intentionally restricted to ABI-stable scalar compiler helpers and
/// local libc/POSIX operations. C++ object layouts, RTTI data objects, exception
/// machinery, networking and proprietary service semantics are not guessed here.
/// </summary>
public static class RuntimePosixRemainingExportsV54
{
    // V54: deterministic runtime/POSIX/compiler-rt functional subset filtered against post-V53 source.
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


    // BEGIN V45 NID Fk7-KFKZi-8
    [SysAbiExport(
        Nid = "Fk7-KFKZi-8",
        ExportName = "acosh",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_acosh(CpuContext ctx)
    {
        return ReturnDouble(ctx, Math.Acosh(GetDouble(ctx, 0)));
    }
    // END V45 NID Fk7-KFKZi-8

    // BEGIN V45 NID 2eQpqTjJ5Y4
    [SysAbiExport(
        Nid = "2eQpqTjJ5Y4",
        ExportName = "asinh",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_asinh(CpuContext ctx)
    {
        return ReturnDouble(ctx, Math.Asinh(GetDouble(ctx, 0)));
    }
    // END V45 NID 2eQpqTjJ5Y4

    // BEGIN V45 NID YjbpxXpi6Zk
    [SysAbiExport(
        Nid = "YjbpxXpi6Zk",
        ExportName = "atanh",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_atanh(CpuContext ctx)
    {
        return ReturnDouble(ctx, Math.Atanh(GetDouble(ctx, 0)));
    }
    // END V45 NID YjbpxXpi6Zk

    // BEGIN V45 NID XJp2C-b0tRU
    [SysAbiExport(
        Nid = "XJp2C-b0tRU",
        ExportName = "acoshf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_acoshf(CpuContext ctx)
    {
        return ReturnFloat(ctx, MathF.Acosh(GetFloat(ctx, 0)));
    }
    // END V45 NID XJp2C-b0tRU

    // BEGIN V45 NID yPPtp1RMihw
    [SysAbiExport(
        Nid = "yPPtp1RMihw",
        ExportName = "asinhf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_asinhf(CpuContext ctx)
    {
        return ReturnFloat(ctx, MathF.Asinh(GetFloat(ctx, 0)));
    }
    // END V45 NID yPPtp1RMihw

    // BEGIN V45 NID cPGyc5FGjy0
    [SysAbiExport(
        Nid = "cPGyc5FGjy0",
        ExportName = "atanhf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_atanhf(CpuContext ctx)
    {
        return ReturnFloat(ctx, MathF.Atanh(GetFloat(ctx, 0)));
    }
    // END V45 NID cPGyc5FGjy0

    // BEGIN V45 NID 5OpjqFs8yv8
    [SysAbiExport(
        Nid = "5OpjqFs8yv8",
        ExportName = "drem",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_drem(CpuContext ctx)
    {
        return ReturnDouble(ctx, Math.IEEERemainder(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // END V45 NID 5OpjqFs8yv8

    // BEGIN V45 NID Gt5RT417EGA
    [SysAbiExport(
        Nid = "Gt5RT417EGA",
        ExportName = "dremf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_dremf(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)Math.IEEERemainder(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // END V45 NID Gt5RT417EGA

    // BEGIN V45 NID gqKfOiJaCOo
    [SysAbiExport(
        Nid = "gqKfOiJaCOo",
        ExportName = "expm1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_expm1(CpuContext ctx)
    {
        return ReturnDouble(ctx, Expm1(GetDouble(ctx, 0)));
    }
    // END V45 NID gqKfOiJaCOo

    // BEGIN V45 NID 3EgxfDRefdw
    [SysAbiExport(
        Nid = "3EgxfDRefdw",
        ExportName = "expm1f",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_expm1f(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)Expm1(GetFloat(ctx, 0)));
    }
    // END V45 NID 3EgxfDRefdw

    // BEGIN V45 NID -VVn74ZyhEs
    [SysAbiExport(
        Nid = "-VVn74ZyhEs",
        ExportName = "difftime",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_difftime(CpuContext ctx)
    {
        return ReturnDouble(ctx, unchecked((long)ctx[CpuRegister.Rdi]) - (double)unchecked((long)ctx[CpuRegister.Rsi]));
    }
    // END V45 NID -VVn74ZyhEs

    // BEGIN V45 NID jMB7EFyu30Y
    [SysAbiExport(
        Nid = "jMB7EFyu30Y",
        ExportName = "sincos",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_sincos(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var sinAddress = ctx[CpuRegister.Rdi];
        var cosAddress = ctx[CpuRegister.Rsi];
        if (sinAddress == 0 || cosAddress == 0) return MemoryFault;
        if (!TryWriteDouble(ctx, sinAddress, Math.Sin(x)) ||
            !TryWriteDouble(ctx, cosAddress, Math.Cos(x)))
            return MemoryFault;
        return Ok;
    }
    // END V45 NID jMB7EFyu30Y

    // BEGIN V45 NID pztV4AF18iI
    private static int _v4711SincosfTraceCount;

    [SysAbiExport(
        Nid = "pztV4AF18iI",
        ExportName = "sincosf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_sincosf(CpuContext ctx)
    {
        ctx.GetXmmRegister(0, out var xLow, out _);
        var x = System.BitConverter.Int32BitsToSingle(unchecked((int)(uint)xLow));
        var sineAddress = ctx[CpuRegister.Rdi];
        var cosineAddress = ctx[CpuRegister.Rsi];
        var sine = System.MathF.Sin(x);
        var cosine = System.MathF.Cos(x);
        var sineBits = System.BitConverter.SingleToInt32Bits(sine);
        var cosineBits = System.BitConverter.SingleToInt32Bits(cosine);

        if (sineAddress == 0 || cosineAddress == 0 ||
            !ctx.TryWriteInt32(sineAddress, sineBits) ||
            !ctx.TryWriteInt32(cosineAddress, cosineBits))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        if (System.String.Equals(
                System.Environment.GetEnvironmentVariable("SHARPEMU_TRACE_SINCOSF_ABI"),
                "1",
                System.StringComparison.Ordinal))
        {
            var traceIndex = System.Threading.Interlocked.Increment(ref _v4711SincosfTraceCount);
            if (traceIndex <= 64)
            {
                System.Console.Error.WriteLine(
                    $"[LIBC-SINCOSF][V47.1.1] #{traceIndex} x={x:R} sin={sine:R} cos={cosine:R} " +
                    $"sin_out=0x{sineAddress:X16} cos_out=0x{cosineAddress:X16} success=1 rip=0x{ctx.Rip:X16}");
            }
        }

        // sincosf is void in the guest ABI. The useful results are returned
        // through the two float pointers; keep RAX deterministic for the HLE bridge.
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }
    // END V45 NID pztV4AF18iI

    // BEGIN V45 NID 5TjaJwkLWxE
    [SysAbiExport(
        Nid = "5TjaJwkLWxE",
        ExportName = "bcmp",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_bcmp(CpuContext ctx)
    {
        var left = ctx[CpuRegister.Rdi];
        var right = ctx[CpuRegister.Rsi];
        var remaining = ctx[CpuRegister.Rdx];
        if (remaining == 0) return ReturnInt(ctx, 0);
        if (left == 0 || right == 0) return MemoryFault;

        var a = ArrayPool<byte>.Shared.Rent(CopyChunk);
        var b = ArrayPool<byte>.Shared.Rent(CopyChunk);
        try
        {
            ulong offset = 0;
            while (remaining != 0)
            {
                var n = (int)Math.Min((ulong)CopyChunk, remaining);
                if (!ctx.Memory.TryRead(left + offset, a.AsSpan(0, n)) ||
                    !ctx.Memory.TryRead(right + offset, b.AsSpan(0, n)))
                    return MemoryFault;
                for (var i = 0; i < n; i++)
                    if (a[i] != b[i]) return ReturnInt(ctx, 1);
                offset += (ulong)n;
                remaining -= (ulong)n;
            }
            return ReturnInt(ctx, 0);
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(a);
            ArrayPool<byte>.Shared.Return(b);
        }
    }
    // END V45 NID 5TjaJwkLWxE

    // BEGIN V45 NID RMo7j0iTPfA
    [SysAbiExport(
        Nid = "RMo7j0iTPfA",
        ExportName = "bcopy",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_bcopy(CpuContext ctx)
    {
        var source = ctx[CpuRegister.Rdi];
        var destination = ctx[CpuRegister.Rsi];
        var length = ctx[CpuRegister.Rdx];
        if (length == 0 || source == destination) return Ok;
        if (source == 0 || destination == 0) return MemoryFault;

        var buffer = ArrayPool<byte>.Shared.Rent(CopyChunk);
        try
        {
            var backward = destination > source && destination - source < length;
            if (backward)
            {
                var remaining = length;
                while (remaining != 0)
                {
                    var n = (int)Math.Min((ulong)CopyChunk, remaining);
                    var offset = remaining - (ulong)n;
                    if (!ctx.Memory.TryRead(source + offset, buffer.AsSpan(0, n)) ||
                        !ctx.Memory.TryWrite(destination + offset, buffer.AsSpan(0, n)))
                        return MemoryFault;
                    remaining = offset;
                }
            }
            else
            {
                ulong offset = 0;
                while (offset < length)
                {
                    var n = (int)Math.Min((ulong)CopyChunk, length - offset);
                    if (!ctx.Memory.TryRead(source + offset, buffer.AsSpan(0, n)) ||
                        !ctx.Memory.TryWrite(destination + offset, buffer.AsSpan(0, n)))
                        return MemoryFault;
                    offset += (ulong)n;
                }
            }
            return Ok;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }
    // END V45 NID RMo7j0iTPfA

    // BEGIN V45 NID Xnrfb2-WhVw
    [SysAbiExport(
        Nid = "Xnrfb2-WhVw",
        ExportName = "strnstr",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_strnstr(CpuContext ctx)
    {
        var haystack = ctx[CpuRegister.Rdi];
        var needle = ctx[CpuRegister.Rsi];
        var maxLength = ctx[CpuRegister.Rdx];
        if (haystack == 0 || needle == 0) return ReturnPointer(ctx, 0);
        if (!TryCStringLength(ctx, needle, out var needleLength)) return MemoryFault;
        if (needleLength == 0) return ReturnPointer(ctx, haystack);
        if ((ulong)needleLength > maxLength) return ReturnPointer(ctx, 0);

        for (ulong i = 0; i + (ulong)needleLength <= maxLength; i++)
        {
            if (!ctx.TryReadByte(haystack + i, out var first)) return MemoryFault;
            if (first == 0) return ReturnPointer(ctx, 0);

            var match = true;
            for (var j = 0; j < needleLength; j++)
            {
                if (!ctx.TryReadByte(haystack + i + (ulong)j, out var hb) ||
                    !ctx.TryReadByte(needle + (ulong)j, out var nb))
                    return MemoryFault;
                if (hb == 0 || hb != nb)
                {
                    match = false;
                    break;
                }
            }
            if (match) return ReturnPointer(ctx, haystack + i);
        }
        return ReturnPointer(ctx, 0);
    }
    // END V45 NID Xnrfb2-WhVw

    // BEGIN V45 NID cJWGxiQPmDQ
    [SysAbiExport(
        Nid = "cJWGxiQPmDQ",
        ExportName = "strsep",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_strsep(CpuContext ctx)
    {
        var stringp = ctx[CpuRegister.Rdi];
        var delim = ctx[CpuRegister.Rsi];
        if (stringp == 0 || delim == 0) return ReturnPointer(ctx, 0);
        if (!TryReadUInt64(ctx, stringp, out var token)) return MemoryFault;
        if (token == 0) return ReturnPointer(ctx, 0);
        if (!TryReadCStringBytes(ctx, delim, out var delimiterBytes)) return MemoryFault;

        for (var i = 0; i < MaxCStringScan; i++)
        {
            var current = token + (ulong)i;
            if (!ctx.TryReadByte(current, out var b)) return MemoryFault;
            if (b == 0)
            {
                if (!TryWriteUInt64(ctx, stringp, 0)) return MemoryFault;
                return ReturnPointer(ctx, token);
            }
            if (ContainsByte(delimiterBytes, b))
            {
                Span<byte> zero = stackalloc byte[1];
                zero[0] = 0;
                if (!ctx.Memory.TryWrite(current, zero) ||
                    !TryWriteUInt64(ctx, stringp, current + 1))
                    return MemoryFault;
                return ReturnPointer(ctx, token);
            }
        }
        return MemoryFault;
    }
    // END V45 NID cJWGxiQPmDQ

    // BEGIN V45 NID +KSnjvZ0NMc
    [SysAbiExport(
        Nid = "+KSnjvZ0NMc",
        ExportName = "srand48",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_srand48(CpuContext ctx)
    {
        var seed = unchecked((uint)ctx[CpuRegister.Rdi]);
        lock (Rand48Gate)
            _rand48State = (((ulong)seed << 16) | 0x330EUL) & Rand48Mask;
        return Ok;
    }
    // END V45 NID +KSnjvZ0NMc

    // BEGIN V45 NID WIg11rA+MRY
    [SysAbiExport(
        Nid = "WIg11rA+MRY",
        ExportName = "drand48",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_drand48(CpuContext ctx)
    {
        ulong state;
        lock (Rand48Gate)
        {
            _rand48State = Next48(_rand48State);
            state = _rand48State;
        }
        return ReturnDouble(ctx, StateToUnitDouble(state));
    }
    // END V45 NID WIg11rA+MRY

    // BEGIN V45 NID 5IpoNfxu84U
    [SysAbiExport(
        Nid = "5IpoNfxu84U",
        ExportName = "lrand48",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_lrand48(CpuContext ctx)
    {
        ulong state;
        lock (Rand48Gate)
        {
            _rand48State = Next48(_rand48State);
            state = _rand48State;
        }
        return ReturnLong(ctx, (long)(state >> 17));
    }
    // END V45 NID 5IpoNfxu84U

    // BEGIN V45 NID k-l0Jth-Go8
    [SysAbiExport(
        Nid = "k-l0Jth-Go8",
        ExportName = "mrand48",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_mrand48(CpuContext ctx)
    {
        ulong state;
        lock (Rand48Gate)
        {
            _rand48State = Next48(_rand48State);
            state = _rand48State;
        }
        return ReturnLong(ctx, unchecked((int)(uint)(state >> 16)));
    }
    // END V45 NID k-l0Jth-Go8

    // BEGIN V45 NID Fncgcl1tnXg
    [SysAbiExport(
        Nid = "Fncgcl1tnXg",
        ExportName = "erand48",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_erand48(CpuContext ctx)
    {
        var address = ctx[CpuRegister.Rdi];
        if (address == 0 || !TryReadRand48(ctx, address, out var state)) return MemoryFault;
        state = Next48(state);
        if (!TryWriteRand48(ctx, address, state)) return MemoryFault;

        return ReturnDouble(ctx, StateToUnitDouble(state));
    }
    // END V45 NID Fncgcl1tnXg

    // BEGIN V45 NID 3wcYIMz8LUo
    [SysAbiExport(
        Nid = "3wcYIMz8LUo",
        ExportName = "nrand48",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_nrand48(CpuContext ctx)
    {
        var address = ctx[CpuRegister.Rdi];
        if (address == 0 || !TryReadRand48(ctx, address, out var state)) return MemoryFault;
        state = Next48(state);
        if (!TryWriteRand48(ctx, address, state)) return MemoryFault;

        return ReturnLong(ctx, (long)(state >> 17));
    }
    // END V45 NID 3wcYIMz8LUo

    // BEGIN V45 NID M7KmRg9CERk
    [SysAbiExport(
        Nid = "M7KmRg9CERk",
        ExportName = "jrand48",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45_jrand48(CpuContext ctx)
    {
        var address = ctx[CpuRegister.Rdi];
        if (address == 0 || !TryReadRand48(ctx, address, out var state)) return MemoryFault;
        state = Next48(state);
        if (!TryWriteRand48(ctx, address, state)) return MemoryFault;

        return ReturnLong(ctx, unchecked((int)(uint)(state >> 16)));
    }
    // END V45 NID M7KmRg9CERk

    // BEGIN V45 NID 3CAYAjL-BLs
    [SysAbiExport(
        Nid = "3CAYAjL-BLs",
        ExportName = "__adddf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___adddf3(CpuContext ctx)
    {
        return ReturnDouble(ctx, GetDouble(ctx, 0) + GetDouble(ctx, 1));
    }
    // END V45 NID 3CAYAjL-BLs

    // BEGIN V45 NID HLDcfGUMNWY
    [SysAbiExport(
        Nid = "HLDcfGUMNWY",
        ExportName = "__subdf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___subdf3(CpuContext ctx)
    {
        return ReturnDouble(ctx, GetDouble(ctx, 0) - GetDouble(ctx, 1));
    }
    // END V45 NID HLDcfGUMNWY

    // BEGIN V45 NID O+Bv-zodKLw
    [SysAbiExport(
        Nid = "O+Bv-zodKLw",
        ExportName = "__muldf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___muldf3(CpuContext ctx)
    {
        return ReturnDouble(ctx, GetDouble(ctx, 0) * GetDouble(ctx, 1));
    }
    // END V45 NID O+Bv-zodKLw

    // BEGIN V45 NID mdGgLADsq8A
    [SysAbiExport(
        Nid = "mdGgLADsq8A",
        ExportName = "__divdf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___divdf3(CpuContext ctx)
    {
        return ReturnDouble(ctx, GetDouble(ctx, 0) / GetDouble(ctx, 1));
    }
    // END V45 NID mdGgLADsq8A

    // BEGIN V45 NID mhIInD5nz8I
    [SysAbiExport(
        Nid = "mhIInD5nz8I",
        ExportName = "__addsf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___addsf3(CpuContext ctx)
    {
        return ReturnFloat(ctx, GetFloat(ctx, 0) + GetFloat(ctx, 1));
    }
    // END V45 NID mhIInD5nz8I

    // BEGIN V45 NID FeyelHfQPzo
    [SysAbiExport(
        Nid = "FeyelHfQPzo",
        ExportName = "__subsf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___subsf3(CpuContext ctx)
    {
        return ReturnFloat(ctx, GetFloat(ctx, 0) - GetFloat(ctx, 1));
    }
    // END V45 NID FeyelHfQPzo

    // BEGIN V45 NID BXmn6hA5o0M
    [SysAbiExport(
        Nid = "BXmn6hA5o0M",
        ExportName = "__mulsf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___mulsf3(CpuContext ctx)
    {
        return ReturnFloat(ctx, GetFloat(ctx, 0) * GetFloat(ctx, 1));
    }
    // END V45 NID BXmn6hA5o0M

    // BEGIN V45 NID nufufTB4jcI
    [SysAbiExport(
        Nid = "nufufTB4jcI",
        ExportName = "__divsf3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___divsf3(CpuContext ctx)
    {
        return ReturnFloat(ctx, GetFloat(ctx, 0) / GetFloat(ctx, 1));
    }
    // END V45 NID nufufTB4jcI

    // BEGIN V45 NID tWI4Ej9k9BY
    [SysAbiExport(
        Nid = "tWI4Ej9k9BY",
        ExportName = "__negdf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___negdf2(CpuContext ctx)
    {
        return ReturnDouble(ctx, -GetDouble(ctx, 0));
    }
    // END V45 NID tWI4Ej9k9BY

    // BEGIN V45 NID 4f+Q5Ka3Ex0
    [SysAbiExport(
        Nid = "4f+Q5Ka3Ex0",
        ExportName = "__negsf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___negsf2(CpuContext ctx)
    {
        return ReturnFloat(ctx, -GetFloat(ctx, 0));
    }
    // END V45 NID 4f+Q5Ka3Ex0

    // BEGIN V45 NID 6zU++1tayjA
    [SysAbiExport(
        Nid = "6zU++1tayjA",
        ExportName = "__extendsfdf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___extendsfdf2(CpuContext ctx)
    {
        return ReturnDouble(ctx, GetFloat(ctx, 0));
    }
    // END V45 NID 6zU++1tayjA

    // BEGIN V45 NID 2M9VZGYPHLI
    [SysAbiExport(
        Nid = "2M9VZGYPHLI",
        ExportName = "__truncdfsf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___truncdfsf2(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)GetDouble(ctx, 0));
    }
    // END V45 NID 2M9VZGYPHLI

    // BEGIN V45 NID 8F52nf7VDS8
    [SysAbiExport(
        Nid = "8F52nf7VDS8",
        ExportName = "__eqdf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___eqdf2(CpuContext ctx)
    {
        return ReturnInt(ctx, EqCompare(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // END V45 NID 8F52nf7VDS8

    // BEGIN V45 NID ocyIiJnJW24
    [SysAbiExport(
        Nid = "ocyIiJnJW24",
        ExportName = "__nedf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___nedf2(CpuContext ctx)
    {
        return ReturnInt(ctx, EqCompare(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // END V45 NID ocyIiJnJW24

    // BEGIN V45 NID LmXIpdHppBM
    [SysAbiExport(
        Nid = "LmXIpdHppBM",
        ExportName = "__eqsf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___eqsf2(CpuContext ctx)
    {
        return ReturnInt(ctx, EqCompare(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // END V45 NID LmXIpdHppBM

    // BEGIN V45 NID OWZ3ZLkgye8
    [SysAbiExport(
        Nid = "OWZ3ZLkgye8",
        ExportName = "__nesf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___nesf2(CpuContext ctx)
    {
        return ReturnInt(ctx, EqCompare(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // END V45 NID OWZ3ZLkgye8

    // BEGIN V45 NID hXA24GbAPBk
    [SysAbiExport(
        Nid = "hXA24GbAPBk",
        ExportName = "__gedf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___gedf2(CpuContext ctx)
    {
        return ReturnInt(ctx, GeCompare(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // END V45 NID hXA24GbAPBk

    // BEGIN V45 NID 1PvImz6yb4M
    [SysAbiExport(
        Nid = "1PvImz6yb4M",
        ExportName = "__gtdf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___gtdf2(CpuContext ctx)
    {
        return ReturnInt(ctx, GeCompare(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // END V45 NID 1PvImz6yb4M

    // BEGIN V45 NID mdLGxBXl6nk
    [SysAbiExport(
        Nid = "mdLGxBXl6nk",
        ExportName = "__gesf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___gesf2(CpuContext ctx)
    {
        return ReturnInt(ctx, GeCompare(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // END V45 NID mdLGxBXl6nk

    // BEGIN V45 NID ICY0Px6zjjo
    [SysAbiExport(
        Nid = "ICY0Px6zjjo",
        ExportName = "__gtsf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___gtsf2(CpuContext ctx)
    {
        return ReturnInt(ctx, GeCompare(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // END V45 NID ICY0Px6zjjo

    // BEGIN V45 NID F78ECICRxho
    [SysAbiExport(
        Nid = "F78ECICRxho",
        ExportName = "__ledf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ledf2(CpuContext ctx)
    {
        return ReturnInt(ctx, LeCompare(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // END V45 NID F78ECICRxho

    // BEGIN V45 NID tcBJa2sYx0w
    [SysAbiExport(
        Nid = "tcBJa2sYx0w",
        ExportName = "__ltdf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ltdf2(CpuContext ctx)
    {
        return ReturnInt(ctx, LeCompare(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // END V45 NID tcBJa2sYx0w

    // BEGIN V45 NID hbiV9vHqTgo
    [SysAbiExport(
        Nid = "hbiV9vHqTgo",
        ExportName = "__lesf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___lesf2(CpuContext ctx)
    {
        return ReturnInt(ctx, LeCompare(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // END V45 NID hbiV9vHqTgo

    // BEGIN V45 NID 259y57ZdZ3I
    [SysAbiExport(
        Nid = "259y57ZdZ3I",
        ExportName = "__ltsf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ltsf2(CpuContext ctx)
    {
        return ReturnInt(ctx, LeCompare(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // END V45 NID 259y57ZdZ3I

    // BEGIN V45 NID EDvkw0WaiOw
    [SysAbiExport(
        Nid = "EDvkw0WaiOw",
        ExportName = "__unorddf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___unorddf2(CpuContext ctx)
    {
        return ReturnInt(ctx, double.IsNaN(GetDouble(ctx, 0)) || double.IsNaN(GetDouble(ctx, 1)) ? 1 : 0);
    }
    // END V45 NID EDvkw0WaiOw

    // BEGIN V45 NID z0OhwgG3Bik
    [SysAbiExport(
        Nid = "z0OhwgG3Bik",
        ExportName = "__unordsf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___unordsf2(CpuContext ctx)
    {
        return ReturnInt(ctx, float.IsNaN(GetFloat(ctx, 0)) || float.IsNaN(GetFloat(ctx, 1)) ? 1 : 0);
    }
    // END V45 NID z0OhwgG3Bik

    // BEGIN V45 NID ECUHmdEfhic
    [SysAbiExport(
        Nid = "ECUHmdEfhic",
        ExportName = "__ashlti3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ashlti3(CpuContext ctx)
    {
        var value = U128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);
        var shift = (int)(ctx[CpuRegister.Rdx] & 127);
        return Return128(ctx, value << shift);
    }
    // END V45 NID ECUHmdEfhic

    // BEGIN V45 NID 7+0ouwmGDww
    [SysAbiExport(
        Nid = "7+0ouwmGDww",
        ExportName = "__ashrti3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ashrti3(CpuContext ctx)
    {
        var value = S128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);
        var shift = (int)(ctx[CpuRegister.Rdx] & 127);
        return Return128(ctx, value >> shift);
    }
    // END V45 NID 7+0ouwmGDww

    // BEGIN V45 NID 1iRAqEqEL0Y
    [SysAbiExport(
        Nid = "1iRAqEqEL0Y",
        ExportName = "__lshrti3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___lshrti3(CpuContext ctx)
    {
        var value = U128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);
        var shift = (int)(ctx[CpuRegister.Rdx] & 127);
        return Return128(ctx, value >> shift);
    }
    // END V45 NID 1iRAqEqEL0Y

    // BEGIN V45 NID jPywoVsPVR8
    [SysAbiExport(
        Nid = "jPywoVsPVR8",
        ExportName = "__clzti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___clzti2(CpuContext ctx)
    {
        return ReturnInt(ctx, LeadingZeros128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID jPywoVsPVR8

    // BEGIN V45 NID olBDzD1rX2Y
    [SysAbiExport(
        Nid = "olBDzD1rX2Y",
        ExportName = "__ctzti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ctzti2(CpuContext ctx)
    {
        return ReturnInt(ctx, TrailingZeros128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID olBDzD1rX2Y

    // BEGIN V45 NID r3tNGoVJ2YA
    [SysAbiExport(
        Nid = "r3tNGoVJ2YA",
        ExportName = "__ffsdi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ffsdi2(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return ReturnInt(ctx, value == 0 ? 0 : BitOperations.TrailingZeroCount(value) + 1);
    }
    // END V45 NID r3tNGoVJ2YA

    // BEGIN V45 NID b54DvYZEHj4
    [SysAbiExport(
        Nid = "b54DvYZEHj4",
        ExportName = "__ffsti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ffsti2(CpuContext ctx)
    {
        var lo = ctx[CpuRegister.Rdi];
        var hi = ctx[CpuRegister.Rsi];
        return ReturnInt(ctx, (lo | hi) == 0 ? 0 : TrailingZeros128(lo, hi) + 1);
    }
    // END V45 NID b54DvYZEHj4

    // BEGIN V45 NID vBP4ytNRXm0
    [SysAbiExport(
        Nid = "vBP4ytNRXm0",
        ExportName = "__parityti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___parityti2(CpuContext ctx)
    {
        return ReturnInt(ctx, PopCount128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]) & 1);
    }
    // END V45 NID vBP4ytNRXm0

    // BEGIN V45 NID l1wz5R6cIxE
    [SysAbiExport(
        Nid = "l1wz5R6cIxE",
        ExportName = "__popcountti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___popcountti2(CpuContext ctx)
    {
        return ReturnInt(ctx, PopCount128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID l1wz5R6cIxE

    // BEGIN V45 NID OvbYtSGnzFk
    [SysAbiExport(
        Nid = "OvbYtSGnzFk",
        ExportName = "__cmpdi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___cmpdi2(CpuContext ctx)
    {
        var a = unchecked((long)ctx[CpuRegister.Rdi]);
        var b = unchecked((long)ctx[CpuRegister.Rsi]);
        return ReturnInt(ctx, a < b ? 0 : a > b ? 2 : 1);
    }
    // END V45 NID OvbYtSGnzFk

    // BEGIN V45 NID SZk+FxWXdAs
    [SysAbiExport(
        Nid = "SZk+FxWXdAs",
        ExportName = "__ucmpdi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ucmpdi2(CpuContext ctx)
    {
        var a = ctx[CpuRegister.Rdi];
        var b = ctx[CpuRegister.Rsi];
        return ReturnInt(ctx, a < b ? 0 : a > b ? 2 : 1);
    }
    // END V45 NID SZk+FxWXdAs

    // BEGIN V45 NID u2kPEkUHfsg
    [SysAbiExport(
        Nid = "u2kPEkUHfsg",
        ExportName = "__cmpti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___cmpti2(CpuContext ctx)
    {
        var a = S128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);
        var b = S128(ctx[CpuRegister.Rdx], ctx[CpuRegister.Rcx]);
        return ReturnInt(ctx, a < b ? 0 : a > b ? 2 : 1);
    }
    // END V45 NID u2kPEkUHfsg

    // BEGIN V45 NID dLmvQfG8am4
    [SysAbiExport(
        Nid = "dLmvQfG8am4",
        ExportName = "__ucmpti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___ucmpti2(CpuContext ctx)
    {
        var a = U128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);
        var b = U128(ctx[CpuRegister.Rdx], ctx[CpuRegister.Rcx]);
        return ReturnInt(ctx, a < b ? 0 : a > b ? 2 : 1);
    }
    // END V45 NID dLmvQfG8am4

    // BEGIN V45 NID Rj4qy44yYUw
    [SysAbiExport(
        Nid = "Rj4qy44yYUw",
        ExportName = "__negdi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___negdi2(CpuContext ctx)
    {
        return ReturnLong(ctx, unchecked(-unchecked((long)ctx[CpuRegister.Rdi])));
    }
    // END V45 NID Rj4qy44yYUw

    // BEGIN V45 NID Zofiv1PMmR4
    [SysAbiExport(
        Nid = "Zofiv1PMmR4",
        ExportName = "__negti2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___negti2(CpuContext ctx)
    {
        return Return128(ctx, -S128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID Zofiv1PMmR4

    // BEGIN V45 NID zhAIFVIN1Ds
    [SysAbiExport(
        Nid = "zhAIFVIN1Ds",
        ExportName = "__multi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___multi3(CpuContext ctx)
    {
        var a = S128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);
        var b = S128(ctx[CpuRegister.Rdx], ctx[CpuRegister.Rcx]);
        return Return128(ctx, a * b);
    }
    // END V45 NID zhAIFVIN1Ds

    // BEGIN V45 NID DDxNvs1a9jM
    [SysAbiExport(
        Nid = "DDxNvs1a9jM",
        ExportName = "__mulosi4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___mulosi4(CpuContext ctx)
    {
        var a = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        var b = unchecked((int)(uint)ctx[CpuRegister.Rsi]);
        var full = (long)a * b;
        var overflow = full < int.MinValue || full > int.MaxValue ? 1 : 0;
        if (!TryWriteInt32(ctx, ctx[CpuRegister.Rdx], overflow)) return MemoryFault;
        return ReturnInt(ctx, unchecked((int)full));
    }
    // END V45 NID DDxNvs1a9jM

    // BEGIN V45 NID wVbBBrqhwdw
    [SysAbiExport(
        Nid = "wVbBBrqhwdw",
        ExportName = "__mulodi4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___mulodi4(CpuContext ctx)
    {
        var a = unchecked((long)ctx[CpuRegister.Rdi]);
        var b = unchecked((long)ctx[CpuRegister.Rsi]);
        var full = (BigInteger)a * b;
        var overflow = full < long.MinValue || full > long.MaxValue ? 1 : 0;
        if (!TryWriteInt32(ctx, ctx[CpuRegister.Rdx], overflow)) return MemoryFault;
        return ReturnLong(ctx, unchecked((long)(ulong)(WrapU128(full) & U64Mask)));
    }
    // END V45 NID wVbBBrqhwdw

    // BEGIN V45 NID +X-5yNFPbDw
    [SysAbiExport(
        Nid = "+X-5yNFPbDw",
        ExportName = "__muloti4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___muloti4(CpuContext ctx)
    {
        var a = S128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]);
        var b = S128(ctx[CpuRegister.Rdx], ctx[CpuRegister.Rcx]);
        var full = a * b;
        var overflow = full < S128Min || full > S128Max ? 1 : 0;
        if (!TryWriteInt32(ctx, ctx[CpuRegister.R8], overflow)) return MemoryFault;
        return Return128(ctx, full);
    }
    // END V45 NID +X-5yNFPbDw

    // BEGIN V45 NID X7A21ChFXPQ
    [SysAbiExport(
        Nid = "X7A21ChFXPQ",
        ExportName = "__floatsidf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floatsidf(CpuContext ctx)
    {
        return ReturnDouble(ctx, unchecked((int)(uint)ctx[CpuRegister.Rdi]));
    }
    // END V45 NID X7A21ChFXPQ

    // BEGIN V45 NID rdht7pwpNfM
    [SysAbiExport(
        Nid = "rdht7pwpNfM",
        ExportName = "__floatsisf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floatsisf(CpuContext ctx)
    {
        return ReturnFloat(ctx, unchecked((int)(uint)ctx[CpuRegister.Rdi]));
    }
    // END V45 NID rdht7pwpNfM

    // BEGIN V45 NID OdvMJCV7Oxo
    [SysAbiExport(
        Nid = "OdvMJCV7Oxo",
        ExportName = "__floatunsidf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floatunsidf(CpuContext ctx)
    {
        return ReturnDouble(ctx, (uint)ctx[CpuRegister.Rdi]);
    }
    // END V45 NID OdvMJCV7Oxo

    // BEGIN V45 NID RC3VBr2l94o
    [SysAbiExport(
        Nid = "RC3VBr2l94o",
        ExportName = "__floatunsisf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floatunsisf(CpuContext ctx)
    {
        return ReturnFloat(ctx, (uint)ctx[CpuRegister.Rdi]);
    }
    // END V45 NID RC3VBr2l94o

    // BEGIN V45 NID EtpM9Qdy8D4
    [SysAbiExport(
        Nid = "EtpM9Qdy8D4",
        ExportName = "__floattidf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floattidf(CpuContext ctx)
    {
        return ReturnDouble(ctx, (double)S128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID EtpM9Qdy8D4

    // BEGIN V45 NID VlDpPYOXL58
    [SysAbiExport(
        Nid = "VlDpPYOXL58",
        ExportName = "__floattisf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floattisf(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)S128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID VlDpPYOXL58

    // BEGIN V45 NID ibs6jIR0Bw0
    [SysAbiExport(
        Nid = "ibs6jIR0Bw0",
        ExportName = "__floatuntidf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floatuntidf(CpuContext ctx)
    {
        return ReturnDouble(ctx, (double)U128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID ibs6jIR0Bw0

    // BEGIN V45 NID KLfd8g4xp+c
    [SysAbiExport(
        Nid = "KLfd8g4xp+c",
        ExportName = "__floatuntisf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___floatuntisf(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)U128(ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi]));
    }
    // END V45 NID KLfd8g4xp+c

    // BEGIN V45 NID dhK16CKwhQg
    [SysAbiExport(
        Nid = "dhK16CKwhQg",
        ExportName = "__isfinite",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isfinite(CpuContext ctx)
    {
        return ReturnInt(ctx, double.IsFinite(GetDouble(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID dhK16CKwhQg

    // BEGIN V45 NID Q8pvJimUWis
    [SysAbiExport(
        Nid = "Q8pvJimUWis",
        ExportName = "__isfinitef",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isfinitef(CpuContext ctx)
    {
        return ReturnInt(ctx, float.IsFinite(GetFloat(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID Q8pvJimUWis

    // BEGIN V45 NID V02oFv+-JzA
    [SysAbiExport(
        Nid = "V02oFv+-JzA",
        ExportName = "__isinf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isinf(CpuContext ctx)
    {
        return ReturnInt(ctx, double.IsInfinity(GetDouble(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID V02oFv+-JzA

    // BEGIN V45 NID rDMyAf1Jhug
    [SysAbiExport(
        Nid = "rDMyAf1Jhug",
        ExportName = "__isinff",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isinff(CpuContext ctx)
    {
        return ReturnInt(ctx, float.IsInfinity(GetFloat(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID rDMyAf1Jhug

    // BEGIN V45 NID GfxAp9Xyiqs
    [SysAbiExport(
        Nid = "GfxAp9Xyiqs",
        ExportName = "__isnan",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isnan(CpuContext ctx)
    {
        return ReturnInt(ctx, double.IsNaN(GetDouble(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID GfxAp9Xyiqs

    // BEGIN V45 NID lA94ZgT+vMM
    [SysAbiExport(
        Nid = "lA94ZgT+vMM",
        ExportName = "__isnanf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isnanf(CpuContext ctx)
    {
        return ReturnInt(ctx, float.IsNaN(GetFloat(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID lA94ZgT+vMM

    // BEGIN V45 NID fGPRa6T+Cu8
    [SysAbiExport(
        Nid = "fGPRa6T+Cu8",
        ExportName = "__isnormal",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isnormal(CpuContext ctx)
    {
        return ReturnInt(ctx, IsNormal(GetDouble(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID fGPRa6T+Cu8

    // BEGIN V45 NID WkYnBHFsmW4
    [SysAbiExport(
        Nid = "WkYnBHFsmW4",
        ExportName = "__isnormalf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___isnormalf(CpuContext ctx)
    {
        return ReturnInt(ctx, IsNormal(GetFloat(ctx, 0)) ? 1 : 0);
    }
    // END V45 NID WkYnBHFsmW4

    // BEGIN V45 NID Rw4J-22tu1U
    [SysAbiExport(
        Nid = "Rw4J-22tu1U",
        ExportName = "__signbit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___signbit(CpuContext ctx)
    {
        var bits = unchecked((ulong)BitConverter.DoubleToInt64Bits(GetDouble(ctx, 0)));
        return ReturnInt(ctx, (bits >> 63) != 0 ? 1 : 0);
    }
    // END V45 NID Rw4J-22tu1U

    // BEGIN V45 NID CjQROLB88a4
    [SysAbiExport(
        Nid = "CjQROLB88a4",
        ExportName = "__signbitf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___signbitf(CpuContext ctx)
    {
        var bits = unchecked((uint)BitConverter.SingleToInt32Bits(GetFloat(ctx, 0)));
        return ReturnInt(ctx, (bits >> 31) != 0 ? 1 : 0);
    }
    // END V45 NID CjQROLB88a4

    // BEGIN V45 NID H+8UBOwfScI
    [SysAbiExport(
        Nid = "H+8UBOwfScI",
        ExportName = "__powidf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___powidf2(CpuContext ctx)
    {
        var value = GetDouble(ctx, 0);
        var exponent = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnDouble(ctx, Math.Pow(value, exponent));
    }
    // END V45 NID H+8UBOwfScI

    // BEGIN V45 NID EiMkgQsOfU0
    [SysAbiExport(
        Nid = "EiMkgQsOfU0",
        ExportName = "__powisf2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int V45___powisf2(CpuContext ctx)
    {
        var value = GetFloat(ctx, 0);
        var exponent = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnFloat(ctx, (float)Math.Pow(value, exponent));
    }
    // END V45 NID EiMkgQsOfU0

}
