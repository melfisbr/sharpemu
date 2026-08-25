// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Buffers;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Globalization;
using System.Threading;
using SharpEmu.HLE;

namespace SharpEmu.Libs.LibcCompat;

/// <summary>
/// V46 evidence-backed runtime expansion.
/// Implements ABI-stable C atomics, compiler builtins, selected libm/libc
/// operations, and MSVC STL vector helper algorithms.
/// No placeholder success handlers are used.
/// </summary>
public static class LibcRuntimeExpansionV46Exports
{
    private const ulong MaxCompatBytes = 256UL * 1024UL * 1024UL;
    private const int MaxCStringBytes = 1024 * 1024;
    private static readonly object AtomicGate = new();
    private static readonly ConcurrentDictionary<ICpuMemory, ulong> StrtokState = new();

    private static int Ok => (int)OrbisGen2Result.ORBIS_GEN2_OK;
    private static int MemoryFault => (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
    private static int InvalidArgument => (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;

    private static int ReturnU64(CpuContext ctx, ulong value)
    {
        ctx[CpuRegister.Rax] = value;
        return Ok;
    }

    private static int ReturnI64(CpuContext ctx, long value) =>
        ReturnU64(ctx, unchecked((ulong)value));

    private static int ReturnU32(CpuContext ctx, uint value) =>
        ReturnU64(ctx, value);

    private static int ReturnI32(CpuContext ctx, int value) =>
        ReturnU64(ctx, unchecked((uint)value));

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

    private static UInt128 ReadUInt128Registers(CpuContext ctx, CpuRegister lowRegister, CpuRegister highRegister) =>
        ((UInt128)ctx[highRegister] << 64) | ctx[lowRegister];

    private static Int128 ReadInt128Registers(CpuContext ctx, CpuRegister lowRegister, CpuRegister highRegister) =>
        unchecked((Int128)ReadUInt128Registers(ctx, lowRegister, highRegister));

    private static int ReturnUInt128(CpuContext ctx, UInt128 value)
    {
        ctx[CpuRegister.Rax] = (ulong)value;
        ctx[CpuRegister.Rdx] = (ulong)(value >> 64);
        return Ok;
    }

    private static int ReturnInt128(CpuContext ctx, Int128 value) =>
        ReturnUInt128(ctx, unchecked((UInt128)value));

    private static bool TryReadScalar(CpuContext ctx, ulong address, int size, out ulong value)
    {
        value = 0;
        switch (size)
        {
            case 1:
                if (!ctx.TryReadByte(address, out var byteValue)) return false;
                value = byteValue;
                return true;
            case 2:
                if (!ctx.TryReadUInt16(address, out var ushortValue)) return false;
                value = ushortValue;
                return true;
            case 4:
                if (!ctx.TryReadUInt32(address, out var uintValue)) return false;
                value = uintValue;
                return true;
            case 8:
                return ctx.TryReadUInt64(address, out value);
            default:
                return false;
        }
    }

    private static bool TryWriteByte(CpuContext ctx, ulong address, byte value)
    {
        Span<byte> buffer = stackalloc byte[1];
        buffer[0] = value;
        return ctx.Memory.TryWrite(address, buffer);
    }

    private static bool TryWriteScalar(CpuContext ctx, ulong address, int size, ulong value) =>
        size switch
        {
            1 => TryWriteByte(ctx, address, unchecked((byte)value)),
            2 => ctx.TryWriteUInt16(address, unchecked((ushort)value)),
            4 => ctx.TryWriteUInt32(address, unchecked((uint)value)),
            8 => ctx.TryWriteUInt64(address, value),
            _ => false,
        };

    private static ulong ScalarMask(int size) =>
        size switch
        {
            1 => 0xFFUL,
            2 => 0xFFFFUL,
            4 => 0xFFFF_FFFFUL,
            _ => ulong.MaxValue,
        };

    private static bool TryReadUInt128(CpuContext ctx, ulong address, out UInt128 value)
    {
        value = 0;
        Span<byte> bytes = stackalloc byte[16];
        if (!ctx.Memory.TryRead(address, bytes))
        {
            return false;
        }

        var low = BinaryPrimitives.ReadUInt64LittleEndian(bytes[..8]);
        var high = BinaryPrimitives.ReadUInt64LittleEndian(bytes[8..]);
        value = ((UInt128)high << 64) | low;
        return true;
    }

    private static bool TryWriteUInt128(CpuContext ctx, ulong address, UInt128 value)
    {
        Span<byte> bytes = stackalloc byte[16];
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[..8], (ulong)value);
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[8..], (ulong)(value >> 64));
        return ctx.Memory.TryWrite(address, bytes);
    }

    private static int AtomicLoad(CpuContext ctx, int size)
    {
        var address = ctx[CpuRegister.Rdi];
        lock (AtomicGate)
        {
            if (!TryReadScalar(ctx, address, size, out var value))
            {
                return MemoryFault;
            }

            return ReturnU64(ctx, value & ScalarMask(size));
        }
    }

    private static int AtomicStore(CpuContext ctx, int size)
    {
        var address = ctx[CpuRegister.Rdi];
        var value = ctx[CpuRegister.Rsi] & ScalarMask(size);
        lock (AtomicGate)
        {
            if (!TryWriteScalar(ctx, address, size, value))
            {
                return MemoryFault;
            }
        }

        Thread.MemoryBarrier();
        return Ok;
    }

    private static int AtomicExchange(CpuContext ctx, int size)
    {
        var address = ctx[CpuRegister.Rdi];
        var desired = ctx[CpuRegister.Rsi] & ScalarMask(size);
        lock (AtomicGate)
        {
            if (!TryReadScalar(ctx, address, size, out var oldValue) ||
                !TryWriteScalar(ctx, address, size, desired))
            {
                return MemoryFault;
            }

            return ReturnU64(ctx, oldValue & ScalarMask(size));
        }
    }

    private static int AtomicFetch(CpuContext ctx, int size, Func<ulong, ulong, ulong> op)
    {
        var address = ctx[CpuRegister.Rdi];
        var operand = ctx[CpuRegister.Rsi] & ScalarMask(size);
        var mask = ScalarMask(size);
        lock (AtomicGate)
        {
            if (!TryReadScalar(ctx, address, size, out var oldValue))
            {
                return MemoryFault;
            }

            oldValue &= mask;
            var newValue = op(oldValue, operand) & mask;
            if (!TryWriteScalar(ctx, address, size, newValue))
            {
                return MemoryFault;
            }

            return ReturnU64(ctx, oldValue);
        }
    }

    private static int AtomicCompareExchange(CpuContext ctx, int size)
    {
        var target = ctx[CpuRegister.Rdi];
        var expectedAddress = ctx[CpuRegister.Rsi];
        var desired = ctx[CpuRegister.Rdx] & ScalarMask(size);
        var mask = ScalarMask(size);

        lock (AtomicGate)
        {
            if (!TryReadScalar(ctx, target, size, out var current) ||
                !TryReadScalar(ctx, expectedAddress, size, out var expected))
            {
                return MemoryFault;
            }

            current &= mask;
            expected &= mask;
            if (current == expected)
            {
                if (!TryWriteScalar(ctx, target, size, desired))
                {
                    return MemoryFault;
                }

                return ReturnI32(ctx, 1);
            }

            if (!TryWriteScalar(ctx, expectedAddress, size, current))
            {
                return MemoryFault;
            }

            return ReturnI32(ctx, 0);
        }
    }

    private static bool TryReadBuffer(CpuContext ctx, ulong address, int count, out byte[] buffer)
    {
        buffer = Array.Empty<byte>();
        if (count < 0 || (ulong)count > MaxCompatBytes || (count != 0 && address == 0))
        {
            return false;
        }

        buffer = new byte[count];
        return count == 0 || ctx.Memory.TryRead(address, buffer);
    }

    private static bool TryWriteBuffer(CpuContext ctx, ulong address, byte[] buffer) =>
        buffer.Length == 0 || (address != 0 && ctx.Memory.TryWrite(address, buffer));

    private static double NextAfter(double x, double y)
    {
        if (double.IsNaN(x) || double.IsNaN(y))
        {
            return x + y;
        }

        if (x == y)
        {
            return y;
        }

        if (x == 0)
        {
            var bits = 1UL | (unchecked((ulong)BitConverter.DoubleToInt64Bits(y)) & 0x8000_0000_0000_0000UL);
            return BitConverter.Int64BitsToDouble(unchecked((long)bits));
        }

        var raw = unchecked((ulong)BitConverter.DoubleToInt64Bits(x));
        if ((x > 0) == (y > x))
        {
            raw++;
        }
        else
        {
            raw--;
        }

        return BitConverter.Int64BitsToDouble(unchecked((long)raw));
    }

    private static float NextAfter(float x, float y)
    {
        if (float.IsNaN(x) || float.IsNaN(y))
        {
            return x + y;
        }

        if (x == y)
        {
            return y;
        }

        if (x == 0)
        {
            var bits = 1U | (unchecked((uint)BitConverter.SingleToInt32Bits(y)) & 0x8000_0000U);
            return BitConverter.Int32BitsToSingle(unchecked((int)bits));
        }

        var raw = unchecked((uint)BitConverter.SingleToInt32Bits(x));
        if ((x > 0) == (y > x))
        {
            raw++;
        }
        else
        {
            raw--;
        }

        return BitConverter.Int32BitsToSingle(unchecked((int)raw));
    }

    private static double Hypot3(double x, double y, double z)
    {
        x = Math.Abs(x);
        y = Math.Abs(y);
        z = Math.Abs(z);

        if (double.IsInfinity(x) || double.IsInfinity(y) || double.IsInfinity(z))
        {
            return double.PositiveInfinity;
        }

        if (double.IsNaN(x) || double.IsNaN(y) || double.IsNaN(z))
        {
            return double.NaN;
        }

        var max = Math.Max(x, Math.Max(y, z));
        if (max == 0)
        {
            return 0;
        }

        x /= max;
        y /= max;
        z /= max;
        return max * Math.Sqrt((x * x) + (y * y) + (z * z));
    }

    private static double ErfApprox(double x)
    {
        if (double.IsNaN(x))
        {
            return double.NaN;
        }

        if (double.IsPositiveInfinity(x))
        {
            return 1;
        }

        if (double.IsNegativeInfinity(x))
        {
            return -1;
        }

        var sign = x < 0 ? -1.0 : 1.0;
        x = Math.Abs(x);

        // Abramowitz-Stegun 7.1.26, max error ~1.5e-7.
        var t = 1.0 / (1.0 + (0.3275911 * x));
        var y = 1.0 -
            (((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t -
               0.284496736) * t + 0.254829592) * t * Math.Exp(-(x * x)));

        return sign * y;
    }

    private static readonly double[] LanczosCoefficients =
    [
        676.5203681218851,
        -1259.1392167224028,
        771.32342877765313,
        -176.61502916214059,
        12.507343278686905,
        -0.13857109526572012,
        9.9843695780195716e-6,
        1.5056327351493116e-7,
    ];

    private static double LogGammaAbs(double z, out int sign)
    {
        sign = 1;
        if (double.IsNaN(z))
        {
            return double.NaN;
        }

        if (double.IsPositiveInfinity(z))
        {
            return double.PositiveInfinity;
        }

        if (z <= 0 && z == Math.Truncate(z))
        {
            return double.PositiveInfinity;
        }

        if (z < 0.5)
        {
            var sin = Math.Sin(Math.PI * z);
            if (sin == 0)
            {
                return double.PositiveInfinity;
            }

            sign = sin < 0 ? -1 : 1;
            var reflected = LogGammaAbs(1.0 - z, out _);
            return Math.Log(Math.PI) - Math.Log(Math.Abs(sin)) - reflected;
        }

        z -= 1.0;
        var x = 0.99999999999980993;
        for (var i = 0; i < LanczosCoefficients.Length; i++)
        {
            x += LanczosCoefficients[i] / (z + i + 1.0);
        }

        var t = z + LanczosCoefficients.Length - 0.5;
        return 0.91893853320467274178 +
               ((z + 0.5) * Math.Log(t)) -
               t +
               Math.Log(x);
    }

    private static double Gamma(double z)
    {
        var lg = LogGammaAbs(z, out var sign);
        if (double.IsNaN(lg))
        {
            return double.NaN;
        }

        if (double.IsPositiveInfinity(lg))
        {
            return sign < 0 ? double.NegativeInfinity : double.PositiveInfinity;
        }

        var value = Math.Exp(lg);
        return sign < 0 ? -value : value;
    }

    private static bool IsAsciiSpace(byte c) =>
        c is 0x20 or 0x09 or 0x0A or 0x0B or 0x0C or 0x0D;

    private static int DigitValue(byte c)
    {
        if (c >= (byte)'0' && c <= (byte)'9') return c - (byte)'0';
        if (c >= (byte)'a' && c <= (byte)'z') return c - (byte)'a' + 10;
        if (c >= (byte)'A' && c <= (byte)'Z') return c - (byte)'A' + 10;
        return -1;
    }

    private static bool TryReadCString(CpuContext ctx, ulong address, out string value)
    {
        value = string.Empty;
        if (address == 0)
        {
            return false;
        }

        var bytes = new byte[256];
        var count = 0;
        while (count < MaxCStringBytes)
        {
            if (!ctx.TryReadByte(address + (ulong)count, out var c))
            {
                return false;
            }

            if (c == 0)
            {
                value = System.Text.Encoding.UTF8.GetString(bytes, 0, count);
                return true;
            }

            if (count == bytes.Length)
            {
                var nextLength = Math.Min(MaxCStringBytes, bytes.Length * 2);
                Array.Resize(ref bytes, nextLength);
            }

            bytes[count++] = c;
        }

        return false;
    }

    private static bool TryWriteEndPointer(CpuContext ctx, ulong endPointerAddress, ulong value) =>
        endPointerAddress == 0 || ctx.TryWriteUInt64(endPointerAddress, value);

    private static ulong ParseUnsignedInteger(
        CpuContext ctx,
        ulong source,
        ulong endPointer,
        int requestedBase,
        int bits,
        out bool negative,
        out bool ok)
    {
        negative = false;
        ok = false;
        if (source == 0 || requestedBase is < 0 or 1 or > 36)
        {
            return 0;
        }

        ulong p = source;
        byte c;
        while (ctx.TryReadByte(p, out c) && IsAsciiSpace(c))
        {
            p++;
        }

        if (!ctx.TryReadByte(p, out c))
        {
            return 0;
        }

        if (c is (byte)'+' or (byte)'-')
        {
            negative = c == (byte)'-';
            p++;
        }

        var numberStart = p;
        var numberBase = requestedBase;

        if (numberBase == 0)
        {
            if (ctx.TryReadByte(p, out c) && c == (byte)'0')
            {
                if (ctx.TryReadByte(p + 1, out var x) && (x == (byte)'x' || x == (byte)'X'))
                {
                    numberBase = 16;
                    p += 2;
                }
                else
                {
                    numberBase = 8;
                }
            }
            else
            {
                numberBase = 10;
            }
        }
        else if (numberBase == 16 &&
                 ctx.TryReadByte(p, out c) &&
                 c == (byte)'0' &&
                 ctx.TryReadByte(p + 1, out var x) &&
                 (x == (byte)'x' || x == (byte)'X'))
        {
            p += 2;
        }

        var digitStart = p;
        UInt128 value = 0;
        var any = false;
        var max = bits == 32 ? (UInt128)uint.MaxValue : ulong.MaxValue;

        while (ctx.TryReadByte(p, out c))
        {
            var digit = DigitValue(c);
            if (digit < 0 || digit >= numberBase)
            {
                break;
            }

            any = true;
            var next = (value * (uint)numberBase) + (uint)digit;
            value = next > max ? max : next;
            p++;
        }

        if (!any)
        {
            ok = TryWriteEndPointer(ctx, endPointer, source);
            return 0;
        }

        ok = TryWriteEndPointer(ctx, endPointer, p);
        if (!ok)
        {
            return 0;
        }

        return (ulong)value;
    }

    private static int ReturnSignedParsed(CpuContext ctx, ulong magnitude, bool negative, int bits)
    {
        if (bits == 32)
        {
            long value;
            if (negative)
            {
                var limit = 1UL << 31;
                value = magnitude >= limit ? int.MinValue : -(long)magnitude;
            }
            else
            {
                value = magnitude > int.MaxValue ? int.MaxValue : (long)magnitude;
            }

            return ReturnI32(ctx, (int)value);
        }

        if (negative)
        {
            var limit = 1UL << 63;
            var value = magnitude >= limit ? long.MinValue : -(long)magnitude;
            return ReturnI64(ctx, value);
        }

        return ReturnI64(ctx, magnitude > long.MaxValue ? long.MaxValue : (long)magnitude);
    }

    private static bool TryParseFloatingToken(
        CpuContext ctx,
        ulong source,
        out double value,
        out ulong endAddress)
    {
        value = 0;
        endAddress = source;
        if (source == 0)
        {
            return false;
        }

        ulong p = source;
        while (ctx.TryReadByte(p, out var ws) && IsAsciiSpace(ws))
        {
            p++;
        }

        var tokenStart = p;
        if (ctx.TryReadByte(p, out var sign) && (sign == (byte)'+' || sign == (byte)'-'))
        {
            p++;
        }

        var numericStart = p;
        var digits = 0;
        while (ctx.TryReadByte(p, out var c) && c >= (byte)'0' && c <= (byte)'9')
        {
            digits++;
            p++;
        }

        if (ctx.TryReadByte(p, out var dot) && dot == (byte)'.')
        {
            p++;
            while (ctx.TryReadByte(p, out var c) && c >= (byte)'0' && c <= (byte)'9')
            {
                digits++;
                p++;
            }
        }

        if (digits == 0)
        {
            // Accept inf/infinity/nan through the full string parser.
            if (!TryReadCString(ctx, tokenStart, out var full))
            {
                return false;
            }

            var lowered = full.ToLowerInvariant();
            var signLength = lowered.StartsWith("+", StringComparison.Ordinal) ||
                             lowered.StartsWith("-", StringComparison.Ordinal) ? 1 : 0;
            var core = lowered[signLength..];
            var coreLength = core.StartsWith("infinity", StringComparison.Ordinal) ? 8 :
                             core.StartsWith("inf", StringComparison.Ordinal) ? 3 :
                             core.StartsWith("nan", StringComparison.Ordinal) ? 3 : 0;
            var length = coreLength == 0 ? 0 : coreLength + signLength;
            if (length == 0)
            {
                endAddress = source;
                return true;
            }

            var token = full[..Math.Min(length, full.Length)];
            if (!double.TryParse(
                    token,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out value))
            {
                value = core.StartsWith("nan", StringComparison.Ordinal)
                    ? double.NaN
                    : lowered.StartsWith("-", StringComparison.Ordinal)
                        ? double.NegativeInfinity
                        : double.PositiveInfinity;
            }

            endAddress = tokenStart + (ulong)length;
            return true;
        }

        var exponentStart = p;
        if (ctx.TryReadByte(p, out var e) && (e == (byte)'e' || e == (byte)'E'))
        {
            var q = p + 1;
            if (ctx.TryReadByte(q, out var es) && (es == (byte)'+' || es == (byte)'-'))
            {
                q++;
            }

            var exponentDigits = 0;
            while (ctx.TryReadByte(q, out var ec) && ec >= (byte)'0' && ec <= (byte)'9')
            {
                exponentDigits++;
                q++;
            }

            if (exponentDigits > 0)
            {
                p = q;
            }
            else
            {
                p = exponentStart;
            }
        }

        var byteCount = checked((int)(p - tokenStart));
        var bytes = new byte[byteCount];
        if (!ctx.Memory.TryRead(tokenStart, bytes))
        {
            return false;
        }

        var tokenText = System.Text.Encoding.ASCII.GetString(bytes);
        if (!double.TryParse(
                tokenText,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out value))
        {
            value = 0;
            endAddress = source;
            return true;
        }

        endAddress = p;
        return true;
    }

    private static bool TryBuildDelimiterSet(CpuContext ctx, ulong delimiterAddress, out bool[] delimiters)
    {
        delimiters = new bool[256];
        if (delimiterAddress == 0)
        {
            return false;
        }

        for (var i = 0; i < 256; i++)
        {
            if (!ctx.TryReadByte(delimiterAddress + (ulong)i, out var c))
            {
                return false;
            }

            if (c == 0)
            {
                return true;
            }

            delimiters[c] = true;
        }

        return true;
    }

    private static int StrtokCore(CpuContext ctx, ulong current, ulong delimiterAddress, Action<ulong> save)
    {
        if (!TryBuildDelimiterSet(ctx, delimiterAddress, out var delimiters))
        {
            return MemoryFault;
        }

        if (current == 0)
        {
            save(0);
            return ReturnU64(ctx, 0);
        }

        while (ctx.TryReadByte(current, out var c) && c != 0 && delimiters[c])
        {
            current++;
        }

        if (!ctx.TryReadByte(current, out var first) || first == 0)
        {
            save(0);
            return ReturnU64(ctx, 0);
        }

        var token = current;
        while (ctx.TryReadByte(current, out var c))
        {
            if (c == 0)
            {
                save(0);
                return ReturnU64(ctx, token);
            }

            if (delimiters[c])
            {
                if (!TryWriteByte(ctx, current, 0))
                {
                    return MemoryFault;
                }

                save(current + 1);
                return ReturnU64(ctx, token);
            }

            current++;
        }

        return MemoryFault;
    }

    private static bool ValidateRange(ulong first, ulong last, int elementSize, out ulong count)
    {
        count = 0;
        if (elementSize <= 0 || last < first)
        {
            return false;
        }

        var bytes = last - first;
        if (bytes > MaxCompatBytes || (bytes % (ulong)elementSize) != 0)
        {
            return false;
        }

        count = bytes / (ulong)elementSize;
        return true;
    }

    private static int StdCount(CpuContext ctx, int elementSize)
    {
        var first = ctx[CpuRegister.Rdi];
        var last = ctx[CpuRegister.Rsi];
        var target = ctx[CpuRegister.Rdx] & ScalarMask(elementSize);

        if (!ValidateRange(first, last, elementSize, out var count))
        {
            return InvalidArgument;
        }

        ulong matches = 0;
        for (ulong i = 0; i < count; i++)
        {
            if (!TryReadScalar(ctx, first + (i * (ulong)elementSize), elementSize, out var value))
            {
                return MemoryFault;
            }

            if ((value & ScalarMask(elementSize)) == target)
            {
                matches++;
            }
        }

        return ReturnU64(ctx, matches);
    }

    private static int StdFind(CpuContext ctx, int elementSize)
    {
        var first = ctx[CpuRegister.Rdi];
        var last = ctx[CpuRegister.Rsi];
        var target = ctx[CpuRegister.Rdx] & ScalarMask(elementSize);

        if (!ValidateRange(first, last, elementSize, out var count))
        {
            return InvalidArgument;
        }

        for (ulong i = 0; i < count; i++)
        {
            var address = first + (i * (ulong)elementSize);
            if (!TryReadScalar(ctx, address, elementSize, out var value))
            {
                return MemoryFault;
            }

            if ((value & ScalarMask(elementSize)) == target)
            {
                return ReturnU64(ctx, address);
            }
        }

        return ReturnU64(ctx, last);
    }

    private static int StdReverse(CpuContext ctx, int elementSize)
    {
        var first = ctx[CpuRegister.Rdi];
        var last = ctx[CpuRegister.Rsi];

        if (!ValidateRange(first, last, elementSize, out var count))
        {
            return InvalidArgument;
        }

        for (ulong i = 0; i < count / 2; i++)
        {
            var left = first + (i * (ulong)elementSize);
            var right = first + ((count - 1 - i) * (ulong)elementSize);

            if (!TryReadScalar(ctx, left, elementSize, out var a) ||
                !TryReadScalar(ctx, right, elementSize, out var b) ||
                !TryWriteScalar(ctx, left, elementSize, b) ||
                !TryWriteScalar(ctx, right, elementSize, a))
            {
                return MemoryFault;
            }
        }

        return Ok;
    }

    private static int StdSwapRanges(CpuContext ctx)
    {
        var first1 = ctx[CpuRegister.Rdi];
        var last1 = ctx[CpuRegister.Rsi];
        var first2 = ctx[CpuRegister.Rdx];

        if (last1 < first1 || last1 - first1 > MaxCompatBytes)
        {
            return InvalidArgument;
        }

        var byteCount = last1 - first1;
        const int chunkSize = 64 * 1024;
        var a = ArrayPool<byte>.Shared.Rent(chunkSize);
        var b = ArrayPool<byte>.Shared.Rent(chunkSize);
        try
        {
            ulong done = 0;
            while (done < byteCount)
            {
                var length = (int)Math.Min((ulong)chunkSize, byteCount - done);
                var spanA = a.AsSpan(0, length);
                var spanB = b.AsSpan(0, length);
                if (!ctx.Memory.TryRead(first1 + done, spanA) ||
                    !ctx.Memory.TryRead(first2 + done, spanB) ||
                    !ctx.Memory.TryWrite(first1 + done, spanB) ||
                    !ctx.Memory.TryWrite(first2 + done, spanA))
                {
                    return MemoryFault;
                }

                done += (ulong)length;
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(a);
            ArrayPool<byte>.Shared.Return(b);
        }

        return Ok;
    }
    // V46_EXPORT_BEGIN:XAqAE803zMg
    [SysAbiExport(
        Nid = "XAqAE803zMg",
        ExportName = "_Atomic_load_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicLoad1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rsi]; // memory_order
        return AtomicLoad(ctx, 1);
    }
    // V46_EXPORT_END:XAqAE803zMg

    // V46_EXPORT_BEGIN:VRX+Ul1oSgE
    [SysAbiExport(
        Nid = "VRX+Ul1oSgE",
        ExportName = "_Atomic_store_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicStore1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicStore(ctx, 1);
    }
    // V46_EXPORT_END:VRX+Ul1oSgE

    // V46_EXPORT_BEGIN:KHJflcH9s84
    [SysAbiExport(
        Nid = "KHJflcH9s84",
        ExportName = "_Atomic_exchange_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicExchange1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicExchange(ctx, 1);
    }
    // V46_EXPORT_END:KHJflcH9s84

    // V46_EXPORT_BEGIN:cO0ldEk3Uko
    [SysAbiExport(
        Nid = "cO0ldEk3Uko",
        ExportName = "_Atomic_fetch_add_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAdd1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 1, static (a, b) => a + b);
    }
    // V46_EXPORT_END:cO0ldEk3Uko

    // V46_EXPORT_BEGIN:-Zfr0ZQheg4
    [SysAbiExport(
        Nid = "-Zfr0ZQheg4",
        ExportName = "_Atomic_fetch_sub_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchSub1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 1, static (a, b) => a - b);
    }
    // V46_EXPORT_END:-Zfr0ZQheg4

    // V46_EXPORT_BEGIN:UVDWssRNEPM
    [SysAbiExport(
        Nid = "UVDWssRNEPM",
        ExportName = "_Atomic_fetch_and_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAnd1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 1, static (a, b) => a & b);
    }
    // V46_EXPORT_END:UVDWssRNEPM

    // V46_EXPORT_BEGIN:K49mqeyzLSk
    [SysAbiExport(
        Nid = "K49mqeyzLSk",
        ExportName = "_Atomic_fetch_or_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchOr1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 1, static (a, b) => a | b);
    }
    // V46_EXPORT_END:K49mqeyzLSk

    // V46_EXPORT_BEGIN:Z9gbzf7fkMU
    [SysAbiExport(
        Nid = "Z9gbzf7fkMU",
        ExportName = "_Atomic_fetch_xor_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchXor1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 1, static (a, b) => a ^ b);
    }
    // V46_EXPORT_END:Z9gbzf7fkMU

    // V46_EXPORT_BEGIN:SwJ-E2FImAo
    [SysAbiExport(
        Nid = "SwJ-E2FImAo",
        ExportName = "_Atomic_compare_exchange_strong_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeStrong1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 1);
    }
    // V46_EXPORT_END:SwJ-E2FImAo

    // V46_EXPORT_BEGIN:rBbtKToRRq4
    [SysAbiExport(
        Nid = "rBbtKToRRq4",
        ExportName = "_Atomic_compare_exchange_weak_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeWeak1(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 1);
    }
    // V46_EXPORT_END:rBbtKToRRq4

    // V46_EXPORT_BEGIN:RBPhCcRhyGI
    [SysAbiExport(
        Nid = "RBPhCcRhyGI",
        ExportName = "_Atomic_is_lock_free_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicIsLockFree1(CpuContext ctx)
    {
        return ReturnI32(ctx, 1);
    }
    // V46_EXPORT_END:RBPhCcRhyGI

    // V46_EXPORT_BEGIN:aYVETR3B8wk
    [SysAbiExport(
        Nid = "aYVETR3B8wk",
        ExportName = "_Atomic_load_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicLoad2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rsi]; // memory_order
        return AtomicLoad(ctx, 2);
    }
    // V46_EXPORT_END:aYVETR3B8wk

    // V46_EXPORT_BEGIN:6WR6sFxcd40
    [SysAbiExport(
        Nid = "6WR6sFxcd40",
        ExportName = "_Atomic_store_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicStore2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicStore(ctx, 2);
    }
    // V46_EXPORT_END:6WR6sFxcd40

    // V46_EXPORT_BEGIN:TbuLWpWuJmc
    [SysAbiExport(
        Nid = "TbuLWpWuJmc",
        ExportName = "_Atomic_exchange_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicExchange2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicExchange(ctx, 2);
    }
    // V46_EXPORT_END:TbuLWpWuJmc

    // V46_EXPORT_BEGIN:9kSWQ8RGtVw
    [SysAbiExport(
        Nid = "9kSWQ8RGtVw",
        ExportName = "_Atomic_fetch_add_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAdd2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 2, static (a, b) => a + b);
    }
    // V46_EXPORT_END:9kSWQ8RGtVw

    // V46_EXPORT_BEGIN:ovtwh8IO3HE
    [SysAbiExport(
        Nid = "ovtwh8IO3HE",
        ExportName = "_Atomic_fetch_sub_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchSub2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 2, static (a, b) => a - b);
    }
    // V46_EXPORT_END:ovtwh8IO3HE

    // V46_EXPORT_BEGIN:PnfhEsZ-5uk
    [SysAbiExport(
        Nid = "PnfhEsZ-5uk",
        ExportName = "_Atomic_fetch_and_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAnd2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 2, static (a, b) => a & b);
    }
    // V46_EXPORT_END:PnfhEsZ-5uk

    // V46_EXPORT_BEGIN:SVIiJg5eppY
    [SysAbiExport(
        Nid = "SVIiJg5eppY",
        ExportName = "_Atomic_fetch_or_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchOr2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 2, static (a, b) => a | b);
    }
    // V46_EXPORT_END:SVIiJg5eppY

    // V46_EXPORT_BEGIN:rpl4rhpUhfg
    [SysAbiExport(
        Nid = "rpl4rhpUhfg",
        ExportName = "_Atomic_fetch_xor_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchXor2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 2, static (a, b) => a ^ b);
    }
    // V46_EXPORT_END:rpl4rhpUhfg

    // V46_EXPORT_BEGIN:qXkZo1LGnfk
    [SysAbiExport(
        Nid = "qXkZo1LGnfk",
        ExportName = "_Atomic_compare_exchange_strong_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeStrong2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 2);
    }
    // V46_EXPORT_END:qXkZo1LGnfk

    // V46_EXPORT_BEGIN:sDOFamOKWBI
    [SysAbiExport(
        Nid = "sDOFamOKWBI",
        ExportName = "_Atomic_compare_exchange_weak_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeWeak2(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 2);
    }
    // V46_EXPORT_END:sDOFamOKWBI

    // V46_EXPORT_BEGIN:QhORYaNkS+U
    [SysAbiExport(
        Nid = "QhORYaNkS+U",
        ExportName = "_Atomic_is_lock_free_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicIsLockFree2(CpuContext ctx)
    {
        return ReturnI32(ctx, 1);
    }
    // V46_EXPORT_END:QhORYaNkS+U

    // V46_EXPORT_BEGIN:cjZEuzHkgng
    [SysAbiExport(
        Nid = "cjZEuzHkgng",
        ExportName = "_Atomic_load_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicLoad4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rsi]; // memory_order
        return AtomicLoad(ctx, 4);
    }
    // V46_EXPORT_END:cjZEuzHkgng

    // V46_EXPORT_BEGIN:HMRMLOwOFIQ
    [SysAbiExport(
        Nid = "HMRMLOwOFIQ",
        ExportName = "_Atomic_store_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicStore4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicStore(ctx, 4);
    }
    // V46_EXPORT_END:HMRMLOwOFIQ

    // V46_EXPORT_BEGIN:-EgDt569OVo
    [SysAbiExport(
        Nid = "-EgDt569OVo",
        ExportName = "_Atomic_exchange_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicExchange4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicExchange(ctx, 4);
    }
    // V46_EXPORT_END:-EgDt569OVo

    // V46_EXPORT_BEGIN:iPBqs+YUUFw
    [SysAbiExport(
        Nid = "iPBqs+YUUFw",
        ExportName = "_Atomic_fetch_add_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAdd4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 4, static (a, b) => a + b);
    }
    // V46_EXPORT_END:iPBqs+YUUFw

    // V46_EXPORT_BEGIN:2HnmKiLmV6s
    [SysAbiExport(
        Nid = "2HnmKiLmV6s",
        ExportName = "_Atomic_fetch_sub_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchSub4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 4, static (a, b) => a - b);
    }
    // V46_EXPORT_END:2HnmKiLmV6s

    // V46_EXPORT_BEGIN:Pn2dnvUmbRA
    [SysAbiExport(
        Nid = "Pn2dnvUmbRA",
        ExportName = "_Atomic_fetch_and_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAnd4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 4, static (a, b) => a & b);
    }
    // V46_EXPORT_END:Pn2dnvUmbRA

    // V46_EXPORT_BEGIN:R5X1i1zcapI
    [SysAbiExport(
        Nid = "R5X1i1zcapI",
        ExportName = "_Atomic_fetch_or_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchOr4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 4, static (a, b) => a | b);
    }
    // V46_EXPORT_END:R5X1i1zcapI

    // V46_EXPORT_BEGIN:-GVEj2QODEI
    [SysAbiExport(
        Nid = "-GVEj2QODEI",
        ExportName = "_Atomic_fetch_xor_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchXor4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 4, static (a, b) => a ^ b);
    }
    // V46_EXPORT_END:-GVEj2QODEI

    // V46_EXPORT_BEGIN:s+LfDF7LKxM
    [SysAbiExport(
        Nid = "s+LfDF7LKxM",
        ExportName = "_Atomic_compare_exchange_strong_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeStrong4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 4);
    }
    // V46_EXPORT_END:s+LfDF7LKxM

    // V46_EXPORT_BEGIN:0AgCOypbQ90
    [SysAbiExport(
        Nid = "0AgCOypbQ90",
        ExportName = "_Atomic_compare_exchange_weak_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeWeak4(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 4);
    }
    // V46_EXPORT_END:0AgCOypbQ90

    // V46_EXPORT_BEGIN:cRYyxdZo1YQ
    [SysAbiExport(
        Nid = "cRYyxdZo1YQ",
        ExportName = "_Atomic_is_lock_free_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicIsLockFree4(CpuContext ctx)
    {
        return ReturnI32(ctx, 1);
    }
    // V46_EXPORT_END:cRYyxdZo1YQ

    // V46_EXPORT_BEGIN:ea-rVHyM3es
    [SysAbiExport(
        Nid = "ea-rVHyM3es",
        ExportName = "_Atomic_load_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicLoad8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rsi]; // memory_order
        return AtomicLoad(ctx, 8);
    }
    // V46_EXPORT_END:ea-rVHyM3es

    // V46_EXPORT_BEGIN:2uKxXHAKynI
    [SysAbiExport(
        Nid = "2uKxXHAKynI",
        ExportName = "_Atomic_store_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicStore8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicStore(ctx, 8);
    }
    // V46_EXPORT_END:2uKxXHAKynI

    // V46_EXPORT_BEGIN:+xoGf-x7nJA
    [SysAbiExport(
        Nid = "+xoGf-x7nJA",
        ExportName = "_Atomic_exchange_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicExchange8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicExchange(ctx, 8);
    }
    // V46_EXPORT_END:+xoGf-x7nJA

    // V46_EXPORT_BEGIN:QVsk3fWNbp0
    [SysAbiExport(
        Nid = "QVsk3fWNbp0",
        ExportName = "_Atomic_fetch_add_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAdd8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 8, static (a, b) => a + b);
    }
    // V46_EXPORT_END:QVsk3fWNbp0

    // V46_EXPORT_BEGIN:T8lH8xXEwIw
    [SysAbiExport(
        Nid = "T8lH8xXEwIw",
        ExportName = "_Atomic_fetch_sub_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchSub8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 8, static (a, b) => a - b);
    }
    // V46_EXPORT_END:T8lH8xXEwIw

    // V46_EXPORT_BEGIN:O6LEoHo2qSQ
    [SysAbiExport(
        Nid = "O6LEoHo2qSQ",
        ExportName = "_Atomic_fetch_and_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchAnd8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 8, static (a, b) => a & b);
    }
    // V46_EXPORT_END:O6LEoHo2qSQ

    // V46_EXPORT_BEGIN:++In3PHBZfw
    [SysAbiExport(
        Nid = "++In3PHBZfw",
        ExportName = "_Atomic_fetch_or_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchOr8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 8, static (a, b) => a | b);
    }
    // V46_EXPORT_END:++In3PHBZfw

    // V46_EXPORT_BEGIN:XKenFBsoh1c
    [SysAbiExport(
        Nid = "XKenFBsoh1c",
        ExportName = "_Atomic_fetch_xor_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFetchXor8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdx]; // memory_order
        return AtomicFetch(ctx, 8, static (a, b) => a ^ b);
    }
    // V46_EXPORT_END:XKenFBsoh1c

    // V46_EXPORT_BEGIN:SZrEVfvcHuA
    [SysAbiExport(
        Nid = "SZrEVfvcHuA",
        ExportName = "_Atomic_compare_exchange_strong_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeStrong8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 8);
    }
    // V46_EXPORT_END:SZrEVfvcHuA

    // V46_EXPORT_BEGIN:bNFLV9DJxdc
    [SysAbiExport(
        Nid = "bNFLV9DJxdc",
        ExportName = "_Atomic_compare_exchange_weak_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicCompareExchangeWeak8(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rcx]; // success order
        _ = ctx[CpuRegister.R8];  // failure order
        return AtomicCompareExchange(ctx, 8);
    }
    // V46_EXPORT_END:bNFLV9DJxdc

    // V46_EXPORT_BEGIN:-3ZujD7JX9c
    [SysAbiExport(
        Nid = "-3ZujD7JX9c",
        ExportName = "_Atomic_is_lock_free_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicIsLockFree8(CpuContext ctx)
    {
        return ReturnI32(ctx, 1);
    }
    // V46_EXPORT_END:-3ZujD7JX9c

    // V46_EXPORT_BEGIN:4CVc6G8JrvQ
    [SysAbiExport(
        Nid = "4CVc6G8JrvQ",
        ExportName = "_Atomic_flag_clear",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFlagClear(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rsi]; // memory_order
        lock (AtomicGate)
        {
            if (!TryWriteByte(ctx, ctx[CpuRegister.Rdi], 0))
            {
                return MemoryFault;
            }
        }

        Thread.MemoryBarrier();
        return Ok;
    }
    // V46_EXPORT_END:4CVc6G8JrvQ

    // V46_EXPORT_BEGIN:Ou6QdDy1f7g
    [SysAbiExport(
        Nid = "Ou6QdDy1f7g",
        ExportName = "_Atomic_flag_test_and_set",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicFlagTestAndSet(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rsi]; // memory_order
        lock (AtomicGate)
        {
            var address = ctx[CpuRegister.Rdi];
            if (!ctx.TryReadByte(address, out var oldValue) ||
                !TryWriteByte(ctx, address, 1))
            {
                return MemoryFault;
            }

            return ReturnI32(ctx, oldValue == 0 ? 0 : 1);
        }
    }
    // V46_EXPORT_END:Ou6QdDy1f7g

    // V46_EXPORT_BEGIN:-7vr7t-uto8
    [SysAbiExport(
        Nid = "-7vr7t-uto8",
        ExportName = "_Atomic_thread_fence",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicThreadFence(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdi]; // memory_order
        Thread.MemoryBarrier();
        return Ok;
    }
    // V46_EXPORT_END:-7vr7t-uto8

    // V46_EXPORT_BEGIN:HfKQ6ZD53sM
    [SysAbiExport(
        Nid = "HfKQ6ZD53sM",
        ExportName = "_Atomic_signal_fence",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int AtomicSignalFence(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdi]; // memory_order
        Thread.MemoryBarrier();
        return Ok;
    }
    // V46_EXPORT_END:HfKQ6ZD53sM
// V46_EXPORT_BEGIN:+WLgzxv5xYA
    [SysAbiExport(
        Nid = "+WLgzxv5xYA",
        ExportName = "__sync_fetch_and_add_16",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_sync_fetch_and_add_16(CpuContext ctx)
    {
        var target = ctx[CpuRegister.Rdi];
        var operand = ReadUInt128Registers(ctx, CpuRegister.Rsi, CpuRegister.Rdx);
        lock (AtomicGate)
        {
            if (!TryReadUInt128(ctx, target, out var oldValue) ||
                !TryWriteUInt128(ctx, target, oldValue + operand))
            {
                return MemoryFault;
            }

            Thread.MemoryBarrier();
            return ReturnUInt128(ctx, oldValue);
        }
    }
    // V46_EXPORT_END:+WLgzxv5xYA

    // V46_EXPORT_BEGIN:Z2I0BWPANGY
    [SysAbiExport(
        Nid = "Z2I0BWPANGY",
        ExportName = "__sync_fetch_and_sub_16",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_sync_fetch_and_sub_16(CpuContext ctx)
    {
        var target = ctx[CpuRegister.Rdi];
        var operand = ReadUInt128Registers(ctx, CpuRegister.Rsi, CpuRegister.Rdx);
        lock (AtomicGate)
        {
            if (!TryReadUInt128(ctx, target, out var oldValue) ||
                !TryWriteUInt128(ctx, target, oldValue - operand))
            {
                return MemoryFault;
            }

            Thread.MemoryBarrier();
            return ReturnUInt128(ctx, oldValue);
        }
    }
    // V46_EXPORT_END:Z2I0BWPANGY

    // V46_EXPORT_BEGIN:XmAquprnaGM
    [SysAbiExport(
        Nid = "XmAquprnaGM",
        ExportName = "__sync_fetch_and_and_16",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_sync_fetch_and_and_16(CpuContext ctx)
    {
        var target = ctx[CpuRegister.Rdi];
        var operand = ReadUInt128Registers(ctx, CpuRegister.Rsi, CpuRegister.Rdx);
        lock (AtomicGate)
        {
            if (!TryReadUInt128(ctx, target, out var oldValue) ||
                !TryWriteUInt128(ctx, target, oldValue & operand))
            {
                return MemoryFault;
            }

            Thread.MemoryBarrier();
            return ReturnUInt128(ctx, oldValue);
        }
    }
    // V46_EXPORT_END:XmAquprnaGM

    // V46_EXPORT_BEGIN:GE4I2XAd4G4
    [SysAbiExport(
        Nid = "GE4I2XAd4G4",
        ExportName = "__sync_fetch_and_or_16",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_sync_fetch_and_or_16(CpuContext ctx)
    {
        var target = ctx[CpuRegister.Rdi];
        var operand = ReadUInt128Registers(ctx, CpuRegister.Rsi, CpuRegister.Rdx);
        lock (AtomicGate)
        {
            if (!TryReadUInt128(ctx, target, out var oldValue) ||
                !TryWriteUInt128(ctx, target, oldValue | operand))
            {
                return MemoryFault;
            }

            Thread.MemoryBarrier();
            return ReturnUInt128(ctx, oldValue);
        }
    }
    // V46_EXPORT_END:GE4I2XAd4G4

    // V46_EXPORT_BEGIN:d5Q-h2wF+-E
    [SysAbiExport(
        Nid = "d5Q-h2wF+-E",
        ExportName = "__sync_fetch_and_xor_16",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_sync_fetch_and_xor_16(CpuContext ctx)
    {
        var target = ctx[CpuRegister.Rdi];
        var operand = ReadUInt128Registers(ctx, CpuRegister.Rsi, CpuRegister.Rdx);
        lock (AtomicGate)
        {
            if (!TryReadUInt128(ctx, target, out var oldValue) ||
                !TryWriteUInt128(ctx, target, oldValue ^ operand))
            {
                return MemoryFault;
            }

            Thread.MemoryBarrier();
            return ReturnUInt128(ctx, oldValue);
        }
    }
    // V46_EXPORT_END:d5Q-h2wF+-E

    // V46_EXPORT_BEGIN:ufZdCzu8nME
    [SysAbiExport(
        Nid = "ufZdCzu8nME",
        ExportName = "__sync_lock_test_and_set_16",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_sync_lock_test_and_set_16(CpuContext ctx)
    {
        var target = ctx[CpuRegister.Rdi];
        var operand = ReadUInt128Registers(ctx, CpuRegister.Rsi, CpuRegister.Rdx);
        lock (AtomicGate)
        {
            if (!TryReadUInt128(ctx, target, out var oldValue) ||
                !TryWriteUInt128(ctx, target, operand))
            {
                return MemoryFault;
            }

            Thread.MemoryBarrier();
            return ReturnUInt128(ctx, oldValue);
        }
    }
    // V46_EXPORT_END:ufZdCzu8nME
// V46_EXPORT_BEGIN:3qQmz11yFaA
    [SysAbiExport(
        Nid = "3qQmz11yFaA",
        ExportName = "__fixsfsi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixsfsi(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        if (float.IsNaN(x)) return ReturnI32(ctx, 0);
        if (x >= int.MaxValue) return ReturnI32(ctx, int.MaxValue);
        if (x <= int.MinValue) return ReturnI32(ctx, int.MinValue);
        return ReturnI32(ctx, (int)x);
    }
    // V46_EXPORT_END:3qQmz11yFaA

    // V46_EXPORT_BEGIN:0eoyU-FoNyk
    [SysAbiExport(
        Nid = "0eoyU-FoNyk",
        ExportName = "__fixsfdi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixsfdi(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        if (float.IsNaN(x)) return ReturnI64(ctx, 0);
        if (x >= long.MaxValue) return ReturnI64(ctx, long.MaxValue);
        if (x <= long.MinValue) return ReturnI64(ctx, long.MinValue);
        return ReturnI64(ctx, (long)x);
    }
    // V46_EXPORT_END:0eoyU-FoNyk

    // V46_EXPORT_BEGIN:saNCRNfjeeg
    [SysAbiExport(
        Nid = "saNCRNfjeeg",
        ExportName = "__fixdfsi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixdfsi(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        if (double.IsNaN(x)) return ReturnI32(ctx, 0);
        if (x >= int.MaxValue) return ReturnI32(ctx, int.MaxValue);
        if (x <= int.MinValue) return ReturnI32(ctx, int.MinValue);
        return ReturnI32(ctx, (int)x);
    }
    // V46_EXPORT_END:saNCRNfjeeg

    // V46_EXPORT_BEGIN:q9SHp+5SOOQ
    [SysAbiExport(
        Nid = "q9SHp+5SOOQ",
        ExportName = "__fixdfdi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixdfdi(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        if (double.IsNaN(x)) return ReturnI64(ctx, 0);
        if (x >= long.MaxValue) return ReturnI64(ctx, long.MaxValue);
        if (x <= long.MinValue) return ReturnI64(ctx, long.MinValue);
        return ReturnI64(ctx, (long)x);
    }
    // V46_EXPORT_END:q9SHp+5SOOQ

    // V46_EXPORT_BEGIN:NcZqFTG-RBs
    [SysAbiExport(
        Nid = "NcZqFTG-RBs",
        ExportName = "__fixunssfsi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixunssfsi(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        if (float.IsNaN(x) || x <= 0) return ReturnU32(ctx, 0);
        if (x >= uint.MaxValue) return ReturnU32(ctx, uint.MaxValue);
        return ReturnU32(ctx, (uint)x);
    }
    // V46_EXPORT_END:NcZqFTG-RBs

    // V46_EXPORT_BEGIN:Qa6HUR3h1k4
    [SysAbiExport(
        Nid = "Qa6HUR3h1k4",
        ExportName = "__fixunssfdi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixunssfdi(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        if (float.IsNaN(x) || x <= 0) return ReturnU64(ctx, 0);
        if (x >= ulong.MaxValue) return ReturnU64(ctx, ulong.MaxValue);
        return ReturnU64(ctx, (ulong)x);
    }
    // V46_EXPORT_END:Qa6HUR3h1k4

    // V46_EXPORT_BEGIN:6WwFtNvnDag
    [SysAbiExport(
        Nid = "6WwFtNvnDag",
        ExportName = "__fixunsdfsi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixunsdfsi(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        if (double.IsNaN(x) || x <= 0) return ReturnU32(ctx, 0);
        if (x >= uint.MaxValue) return ReturnU32(ctx, uint.MaxValue);
        return ReturnU32(ctx, (uint)x);
    }
    // V46_EXPORT_END:6WwFtNvnDag

    // V46_EXPORT_BEGIN:h8nbSvw0s+M
    [SysAbiExport(
        Nid = "h8nbSvw0s+M",
        ExportName = "__fixunsdfdi",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixunsdfdi(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        if (double.IsNaN(x) || x <= 0) return ReturnU64(ctx, 0);
        if (x >= ulong.MaxValue) return ReturnU64(ctx, ulong.MaxValue);
        return ReturnU64(ctx, (ulong)x);
    }
    // V46_EXPORT_END:h8nbSvw0s+M
// V46_EXPORT_BEGIN:IHq2IaY4UGg
    [SysAbiExport(
        Nid = "IHq2IaY4UGg",
        ExportName = "__fixsfti",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixsfti(CpuContext ctx)
    {
        var x = (double)GetFloat(ctx, 0);
        if (double.IsNaN(x)) return ReturnInt128(ctx, 0);
        if (x >= (double)Int128.MaxValue) return ReturnInt128(ctx, Int128.MaxValue);
        if (x <= (double)Int128.MinValue) return ReturnInt128(ctx, Int128.MinValue);
        return ReturnInt128(ctx, (Int128)x);
    }
    // V46_EXPORT_END:IHq2IaY4UGg

    // V46_EXPORT_BEGIN:cY4yCWdcTXE
    [SysAbiExport(
        Nid = "cY4yCWdcTXE",
        ExportName = "__fixdfti",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixdfti(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        if (double.IsNaN(x)) return ReturnInt128(ctx, 0);
        if (x >= (double)Int128.MaxValue) return ReturnInt128(ctx, Int128.MaxValue);
        if (x <= (double)Int128.MinValue) return ReturnInt128(ctx, Int128.MinValue);
        return ReturnInt128(ctx, (Int128)x);
    }
    // V46_EXPORT_END:cY4yCWdcTXE

    // V46_EXPORT_BEGIN:mCESRUqZ+mw
    [SysAbiExport(
        Nid = "mCESRUqZ+mw",
        ExportName = "__fixunssfti",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixunssfti(CpuContext ctx)
    {
        var x = (double)GetFloat(ctx, 0);
        if (double.IsNaN(x) || x <= 0) return ReturnUInt128(ctx, 0);
        if (x >= (double)UInt128.MaxValue) return ReturnUInt128(ctx, UInt128.MaxValue);
        return ReturnUInt128(ctx, (UInt128)x);
    }
    // V46_EXPORT_END:mCESRUqZ+mw

    // V46_EXPORT_BEGIN:rLuypv9iADw
    [SysAbiExport(
        Nid = "rLuypv9iADw",
        ExportName = "__fixunsdfti",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fixunsdfti(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        if (double.IsNaN(x) || x <= 0) return ReturnUInt128(ctx, 0);
        if (x >= (double)UInt128.MaxValue) return ReturnUInt128(ctx, UInt128.MaxValue);
        return ReturnUInt128(ctx, (UInt128)x);
    }
    // V46_EXPORT_END:rLuypv9iADw

    // V46_EXPORT_BEGIN:YKbL5KR6RDI
    [SysAbiExport(
        Nid = "YKbL5KR6RDI",
        ExportName = "fma",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fma(CpuContext ctx)
    {
        return ReturnDouble(ctx, Math.FusedMultiplyAdd(GetDouble(ctx, 0), GetDouble(ctx, 1), GetDouble(ctx, 2)));
    }
    // V46_EXPORT_END:YKbL5KR6RDI

    // V46_EXPORT_BEGIN:RpTR+VY15ss
    [SysAbiExport(
        Nid = "RpTR+VY15ss",
        ExportName = "fmaf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_fmaf(CpuContext ctx)
    {
        return ReturnFloat(ctx, MathF.FusedMultiplyAdd(GetFloat(ctx, 0), GetFloat(ctx, 1), GetFloat(ctx, 2)));
    }
    // V46_EXPORT_END:RpTR+VY15ss

    // V46_EXPORT_BEGIN:h6pVBKjcLiU
    [SysAbiExport(
        Nid = "h6pVBKjcLiU",
        ExportName = "ilogb",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_ilogb(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var value = double.IsNaN(x) || x == 0 ? int.MinValue :
                    double.IsInfinity(x) ? int.MaxValue :
                    Math.ILogB(Math.Abs(x));
        return ReturnI32(ctx, value);
    }
    // V46_EXPORT_END:h6pVBKjcLiU

    // V46_EXPORT_BEGIN:0dQrYWd7g94
    [SysAbiExport(
        Nid = "0dQrYWd7g94",
        ExportName = "ilogbf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_ilogbf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var value = float.IsNaN(x) || x == 0 ? int.MinValue :
                    float.IsInfinity(x) ? int.MaxValue :
                    Math.ILogB(Math.Abs((double)x));
        return ReturnI32(ctx, value);
    }
    // V46_EXPORT_END:0dQrYWd7g94

    // V46_EXPORT_BEGIN:VfsML+n9cDM
    [SysAbiExport(
        Nid = "VfsML+n9cDM",
        ExportName = "log1p",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_log1p(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var value = Math.Abs(x) < 1e-8 ? x - ((x * x) / 2.0) + ((x * x * x) / 3.0) : Math.Log(1.0 + x);
        return ReturnDouble(ctx, value);
    }
    // V46_EXPORT_END:VfsML+n9cDM

    // V46_EXPORT_BEGIN:MFe91s8apQk
    [SysAbiExport(
        Nid = "MFe91s8apQk",
        ExportName = "log1pf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_log1pf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var value = Math.Abs(x) < 1e-4f ? x - ((x * x) / 2.0f) + ((x * x * x) / 3.0f) : MathF.Log(1.0f + x);
        return ReturnFloat(ctx, value);
    }
    // V46_EXPORT_END:MFe91s8apQk

    // V46_EXPORT_BEGIN:owKuegZU4ew
    [SysAbiExport(
        Nid = "owKuegZU4ew",
        ExportName = "logb",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_logb(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        if (double.IsNaN(x)) return ReturnDouble(ctx, double.NaN);
        if (x == 0) return ReturnDouble(ctx, double.NegativeInfinity);
        if (double.IsInfinity(x)) return ReturnDouble(ctx, double.PositiveInfinity);
        return ReturnDouble(ctx, Math.ILogB(Math.Abs(x)));
    }
    // V46_EXPORT_END:owKuegZU4ew

    // V46_EXPORT_BEGIN:RWqyr1OKuw4
    [SysAbiExport(
        Nid = "RWqyr1OKuw4",
        ExportName = "logbf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_logbf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        if (float.IsNaN(x)) return ReturnFloat(ctx, float.NaN);
        if (x == 0) return ReturnFloat(ctx, float.NegativeInfinity);
        if (float.IsInfinity(x)) return ReturnFloat(ctx, float.PositiveInfinity);
        return ReturnFloat(ctx, Math.ILogB(Math.Abs((double)x)));
    }
    // V46_EXPORT_END:RWqyr1OKuw4

    // V46_EXPORT_BEGIN:h+J60RRlfnk
    [SysAbiExport(
        Nid = "h+J60RRlfnk",
        ExportName = "nextafter",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_nextafter(CpuContext ctx)
    {
        return ReturnDouble(ctx, NextAfter(GetDouble(ctx, 0), GetDouble(ctx, 1)));
    }
    // V46_EXPORT_END:h+J60RRlfnk

    // V46_EXPORT_BEGIN:3m2ro+Di+Ck
    [SysAbiExport(
        Nid = "3m2ro+Di+Ck",
        ExportName = "nextafterf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_nextafterf(CpuContext ctx)
    {
        return ReturnFloat(ctx, NextAfter(GetFloat(ctx, 0), GetFloat(ctx, 1)));
    }
    // V46_EXPORT_END:3m2ro+Di+Ck

    // V46_EXPORT_BEGIN:7Jp3g-qTgZw
    [SysAbiExport(
        Nid = "7Jp3g-qTgZw",
        ExportName = "scalbln",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_scalbln(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var exponent = unchecked((long)ctx[CpuRegister.Rdi]);
        if (exponent > int.MaxValue) return ReturnDouble(ctx, x == 0 ? x : Math.CopySign(double.PositiveInfinity, x));
        if (exponent < int.MinValue) return ReturnDouble(ctx, Math.CopySign(0.0, x));
        return ReturnDouble(ctx, Math.ScaleB(x, (int)exponent));
    }
    // V46_EXPORT_END:7Jp3g-qTgZw

    // V46_EXPORT_BEGIN:S6LHwvK4h8c
    [SysAbiExport(
        Nid = "S6LHwvK4h8c",
        ExportName = "scalblnf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_scalblnf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var exponent = unchecked((long)ctx[CpuRegister.Rdi]);
        if (exponent > int.MaxValue) return ReturnFloat(ctx, x == 0 ? x : MathF.CopySign(float.PositiveInfinity, x));
        if (exponent < int.MinValue) return ReturnFloat(ctx, MathF.CopySign(0.0f, x));
        return ReturnFloat(ctx, (float)Math.ScaleB(x, (int)exponent));
    }
    // V46_EXPORT_END:S6LHwvK4h8c

    // V46_EXPORT_BEGIN:DZU+K1wozGI
    [SysAbiExport(
        Nid = "DZU+K1wozGI",
        ExportName = "nanf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_nanf(CpuContext ctx)
    {
        _ = ctx[CpuRegister.Rdi]; // implementation-defined payload string
        return ReturnFloat(ctx, float.NaN);
    }
    // V46_EXPORT_END:DZU+K1wozGI

    // V46_EXPORT_BEGIN:oXgaqGVnW5o
    [SysAbiExport(
        Nid = "oXgaqGVnW5o",
        ExportName = "erf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_erf(CpuContext ctx)
    {
        return ReturnDouble(ctx, ErfApprox(GetDouble(ctx, 0)));
    }
    // V46_EXPORT_END:oXgaqGVnW5o

    // V46_EXPORT_BEGIN:RePA3bDBJqo
    [SysAbiExport(
        Nid = "RePA3bDBJqo",
        ExportName = "erff",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_erff(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)ErfApprox(GetFloat(ctx, 0)));
    }
    // V46_EXPORT_END:RePA3bDBJqo

    // V46_EXPORT_BEGIN:arIKLlen2sg
    [SysAbiExport(
        Nid = "arIKLlen2sg",
        ExportName = "erfc",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_erfc(CpuContext ctx)
    {
        return ReturnDouble(ctx, 1.0 - ErfApprox(GetDouble(ctx, 0)));
    }
    // V46_EXPORT_END:arIKLlen2sg

    // V46_EXPORT_BEGIN:IvF98yl5u4s
    [SysAbiExport(
        Nid = "IvF98yl5u4s",
        ExportName = "erfcf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_erfcf(CpuContext ctx)
    {
        return ReturnFloat(ctx, 1.0f - (float)ErfApprox(GetFloat(ctx, 0)));
    }
    // V46_EXPORT_END:IvF98yl5u4s

    // V46_EXPORT_BEGIN:b7J3q7-UABY
    [SysAbiExport(
        Nid = "b7J3q7-UABY",
        ExportName = "tgamma",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_tgamma(CpuContext ctx)
    {
        return ReturnDouble(ctx, Gamma(GetDouble(ctx, 0)));
    }
    // V46_EXPORT_END:b7J3q7-UABY

    // V46_EXPORT_BEGIN:B2ZbqV9geCM
    [SysAbiExport(
        Nid = "B2ZbqV9geCM",
        ExportName = "tgammaf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_tgammaf(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)Gamma(GetFloat(ctx, 0)));
    }
    // V46_EXPORT_END:B2ZbqV9geCM

    // V46_EXPORT_BEGIN:o-kMHRBvkbQ
    [SysAbiExport(
        Nid = "o-kMHRBvkbQ",
        ExportName = "lgamma",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_lgamma(CpuContext ctx)
    {
        var value = LogGammaAbs(GetDouble(ctx, 0), out _);
        return ReturnDouble(ctx, value);
    }
    // V46_EXPORT_END:o-kMHRBvkbQ

    // V46_EXPORT_BEGIN:i-ifjh3SLBU
    [SysAbiExport(
        Nid = "i-ifjh3SLBU",
        ExportName = "lgammaf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_lgammaf(CpuContext ctx)
    {
        var value = LogGammaAbs(GetFloat(ctx, 0), out _);
        return ReturnFloat(ctx, (float)value);
    }
    // V46_EXPORT_END:i-ifjh3SLBU

    // V46_EXPORT_BEGIN:EjL+gY1G2lk
    [SysAbiExport(
        Nid = "EjL+gY1G2lk",
        ExportName = "lgamma_r",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_lgamma_r(CpuContext ctx)
    {
        var value = LogGammaAbs(GetDouble(ctx, 0), out var sign);
        var signAddress = ctx[CpuRegister.Rdi];
        if (signAddress == 0 || !ctx.TryWriteInt32(signAddress, sign)) return MemoryFault;
        return ReturnDouble(ctx, value);
    }
    // V46_EXPORT_END:EjL+gY1G2lk

    // V46_EXPORT_BEGIN:RlGUiqyKf9I
    [SysAbiExport(
        Nid = "RlGUiqyKf9I",
        ExportName = "lgammaf_r",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_lgammaf_r(CpuContext ctx)
    {
        var value = LogGammaAbs(GetFloat(ctx, 0), out var sign);
        var signAddress = ctx[CpuRegister.Rdi];
        if (signAddress == 0 || !ctx.TryWriteInt32(signAddress, sign)) return MemoryFault;
        return ReturnFloat(ctx, (float)value);
    }
    // V46_EXPORT_END:RlGUiqyKf9I

    // V46_EXPORT_BEGIN:2HzgScoQq9o
    [SysAbiExport(
        Nid = "2HzgScoQq9o",
        ExportName = "hypot3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_hypot3(CpuContext ctx)
    {
        return ReturnDouble(ctx, Hypot3(GetDouble(ctx, 0), GetDouble(ctx, 1), GetDouble(ctx, 2)));
    }
    // V46_EXPORT_END:2HzgScoQq9o

    // V46_EXPORT_BEGIN:xlRcc7Rcqgo
    [SysAbiExport(
        Nid = "xlRcc7Rcqgo",
        ExportName = "hypot3f",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_hypot3f(CpuContext ctx)
    {
        return ReturnFloat(ctx, (float)Hypot3(GetFloat(ctx, 0), GetFloat(ctx, 1), GetFloat(ctx, 2)));
    }
    // V46_EXPORT_END:xlRcc7Rcqgo

    // V46_EXPORT_BEGIN:5XVWOcxpuJ4
    [SysAbiExport(
        Nid = "5XVWOcxpuJ4",
        ExportName = "__std_count_trivial_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_count_trivial_1(CpuContext ctx)
    {
        return StdCount(ctx, 1);
    }
    // V46_EXPORT_END:5XVWOcxpuJ4

    // V46_EXPORT_BEGIN:aRtxlukU9WQ
    [SysAbiExport(
        Nid = "aRtxlukU9WQ",
        ExportName = "__std_find_trivial_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_find_trivial_1(CpuContext ctx)
    {
        return StdFind(ctx, 1);
    }
    // V46_EXPORT_END:aRtxlukU9WQ

    // V46_EXPORT_BEGIN:tJtD8WHnb04
    [SysAbiExport(
        Nid = "tJtD8WHnb04",
        ExportName = "__std_reverse_trivially_swappable_1",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_reverse_trivially_swappable_1(CpuContext ctx)
    {
        return StdReverse(ctx, 1);
    }
    // V46_EXPORT_END:tJtD8WHnb04

    // V46_EXPORT_BEGIN:eB0BxBBkGTI
    [SysAbiExport(
        Nid = "eB0BxBBkGTI",
        ExportName = "__std_count_trivial_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_count_trivial_2(CpuContext ctx)
    {
        return StdCount(ctx, 2);
    }
    // V46_EXPORT_END:eB0BxBBkGTI

    // V46_EXPORT_BEGIN:Oa7AB0wiixE
    [SysAbiExport(
        Nid = "Oa7AB0wiixE",
        ExportName = "__std_find_trivial_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_find_trivial_2(CpuContext ctx)
    {
        return StdFind(ctx, 2);
    }
    // V46_EXPORT_END:Oa7AB0wiixE

    // V46_EXPORT_BEGIN:yRpOciDxbfE
    [SysAbiExport(
        Nid = "yRpOciDxbfE",
        ExportName = "__std_reverse_trivially_swappable_2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_reverse_trivially_swappable_2(CpuContext ctx)
    {
        return StdReverse(ctx, 2);
    }
    // V46_EXPORT_END:yRpOciDxbfE

    // V46_EXPORT_BEGIN:2Zu5doVSeC8
    [SysAbiExport(
        Nid = "2Zu5doVSeC8",
        ExportName = "__std_count_trivial_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_count_trivial_4(CpuContext ctx)
    {
        return StdCount(ctx, 4);
    }
    // V46_EXPORT_END:2Zu5doVSeC8

    // V46_EXPORT_BEGIN:Zf7ewes1VtY
    [SysAbiExport(
        Nid = "Zf7ewes1VtY",
        ExportName = "__std_find_trivial_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_find_trivial_4(CpuContext ctx)
    {
        return StdFind(ctx, 4);
    }
    // V46_EXPORT_END:Zf7ewes1VtY

    // V46_EXPORT_BEGIN:O3aVZ5BqPr4
    [SysAbiExport(
        Nid = "O3aVZ5BqPr4",
        ExportName = "__std_reverse_trivially_swappable_4",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_reverse_trivially_swappable_4(CpuContext ctx)
    {
        return StdReverse(ctx, 4);
    }
    // V46_EXPORT_END:O3aVZ5BqPr4

    // V46_EXPORT_BEGIN:zoGsxctWW5M
    [SysAbiExport(
        Nid = "zoGsxctWW5M",
        ExportName = "__std_count_trivial_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_count_trivial_8(CpuContext ctx)
    {
        return StdCount(ctx, 8);
    }
    // V46_EXPORT_END:zoGsxctWW5M

    // V46_EXPORT_BEGIN:3sssb+7Wn9M
    [SysAbiExport(
        Nid = "3sssb+7Wn9M",
        ExportName = "__std_find_trivial_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_find_trivial_8(CpuContext ctx)
    {
        return StdFind(ctx, 8);
    }
    // V46_EXPORT_END:3sssb+7Wn9M

    // V46_EXPORT_BEGIN:3310gBtLU9M
    [SysAbiExport(
        Nid = "3310gBtLU9M",
        ExportName = "__std_reverse_trivially_swappable_8",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_reverse_trivially_swappable_8(CpuContext ctx)
    {
        return StdReverse(ctx, 8);
    }
    // V46_EXPORT_END:3310gBtLU9M

    // V46_EXPORT_BEGIN:Ea3sKNHWn9U
    [SysAbiExport(
        Nid = "Ea3sKNHWn9U",
        ExportName = "__std_swap_ranges_trivially_swappable_noalias",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_std_swap_ranges_trivially_swappable_noalias(CpuContext ctx)
    {
        return StdSwapRanges(ctx);
    }
    // V46_EXPORT_END:Ea3sKNHWn9U

    // V46_EXPORT_BEGIN:+my9jdHCMIQ
    [SysAbiExport(
        Nid = "+my9jdHCMIQ",
        ExportName = "atol",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_atol(CpuContext ctx)
    {
        var source = ctx[CpuRegister.Rdi];
        var magnitude = ParseUnsignedInteger(ctx, source, 0, 10, 64, out var negative, out var ok);
        if (!ok && source == 0) return InvalidArgument;
        return ReturnSignedParsed(ctx, magnitude, negative, 64);
    }
    // V46_EXPORT_END:+my9jdHCMIQ

    // V46_EXPORT_BEGIN:mXlxhmLNMPg
    [SysAbiExport(
        Nid = "mXlxhmLNMPg",
        ExportName = "strtol",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtol(CpuContext ctx)
    {
        var magnitude = ParseUnsignedInteger(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            64,
            out var negative,
            out var ok);
        if (!ok) return InvalidArgument;
        return ReturnSignedParsed(ctx, magnitude, negative, 64);
    }
    // V46_EXPORT_END:mXlxhmLNMPg

    // V46_EXPORT_BEGIN:QxmSHBCuKTk
    [SysAbiExport(
        Nid = "QxmSHBCuKTk",
        ExportName = "strtoul",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtoul(CpuContext ctx)
    {
        var magnitude = ParseUnsignedInteger(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            64,
            out var negative,
            out var ok);
        if (!ok) return InvalidArgument;
        return ReturnU64(ctx, negative ? unchecked(0UL - magnitude) : magnitude);
    }
    // V46_EXPORT_END:QxmSHBCuKTk

    // V46_EXPORT_BEGIN:VOBg+iNwB-4
    [SysAbiExport(
        Nid = "VOBg+iNwB-4",
        ExportName = "strtoll",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtoll(CpuContext ctx)
    {
        var magnitude = ParseUnsignedInteger(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            64,
            out var negative,
            out var ok);
        if (!ok) return InvalidArgument;
        return ReturnSignedParsed(ctx, magnitude, negative, 64);
    }
    // V46_EXPORT_END:VOBg+iNwB-4

    // V46_EXPORT_BEGIN:5OqszGpy7Mg
    [SysAbiExport(
        Nid = "5OqszGpy7Mg",
        ExportName = "strtoull",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtoull(CpuContext ctx)
    {
        var magnitude = ParseUnsignedInteger(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            64,
            out var negative,
            out var ok);
        if (!ok) return InvalidArgument;
        return ReturnU64(ctx, negative ? unchecked(0UL - magnitude) : magnitude);
    }
    // V46_EXPORT_END:5OqszGpy7Mg

    // V46_EXPORT_BEGIN:q5MWYCDfu3c
    [SysAbiExport(
        Nid = "q5MWYCDfu3c",
        ExportName = "strtoimax",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtoimax(CpuContext ctx)
    {
        var magnitude = ParseUnsignedInteger(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            64,
            out var negative,
            out var ok);
        if (!ok) return InvalidArgument;
        return ReturnSignedParsed(ctx, magnitude, negative, 64);
    }
    // V46_EXPORT_END:q5MWYCDfu3c

    // V46_EXPORT_BEGIN:QNyUWGXmXNc
    [SysAbiExport(
        Nid = "QNyUWGXmXNc",
        ExportName = "strtoumax",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtoumax(CpuContext ctx)
    {
        var magnitude = ParseUnsignedInteger(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            64,
            out var negative,
            out var ok);
        if (!ok) return InvalidArgument;
        return ReturnU64(ctx, negative ? unchecked(0UL - magnitude) : magnitude);
    }
    // V46_EXPORT_END:QNyUWGXmXNc

    // V46_EXPORT_BEGIN:2vDqwBlpF-o
    [SysAbiExport(
        Nid = "2vDqwBlpF-o",
        ExportName = "strtod",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtod(CpuContext ctx)
    {
        var source = ctx[CpuRegister.Rdi];
        var endPointer = ctx[CpuRegister.Rsi];
        if (!TryParseFloatingToken(ctx, source, out var value, out var endAddress) ||
            !TryWriteEndPointer(ctx, endPointer, endAddress))
        {
            return MemoryFault;
        }

        return ReturnDouble(ctx, value);
    }
    // V46_EXPORT_END:2vDqwBlpF-o

    // V46_EXPORT_BEGIN:xENtRue8dpI
    [SysAbiExport(
        Nid = "xENtRue8dpI",
        ExportName = "strtof",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtof(CpuContext ctx)
    {
        var source = ctx[CpuRegister.Rdi];
        var endPointer = ctx[CpuRegister.Rsi];
        if (!TryParseFloatingToken(ctx, source, out var value, out var endAddress) ||
            !TryWriteEndPointer(ctx, endPointer, endAddress))
        {
            return MemoryFault;
        }

        return ReturnFloat(ctx, (float)value);
    }
    // V46_EXPORT_END:xENtRue8dpI

    // V46_EXPORT_BEGIN:enqPGLfmVNU
    [SysAbiExport(
        Nid = "enqPGLfmVNU",
        ExportName = "strtok_r",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtokr(CpuContext ctx)
    {
        var input = ctx[CpuRegister.Rdi];
        var delimiters = ctx[CpuRegister.Rsi];
        var savePointer = ctx[CpuRegister.Rdx];
        if (savePointer == 0) return InvalidArgument;

        ulong current;
        if (input != 0)
        {
            current = input;
        }
        else if (!ctx.TryReadUInt64(savePointer, out current))
        {
            return MemoryFault;
        }

        ulong nextValue = 0;
        var result = StrtokCore(ctx, current, delimiters, next => nextValue = next);
        if (result != Ok && !ctx.WasRaxWritten)
        {
            return result;
        }

        if (!ctx.TryWriteUInt64(savePointer, nextValue))
        {
            return MemoryFault;
        }

        return result;
    }
    // V46_EXPORT_END:enqPGLfmVNU

    // V46_EXPORT_BEGIN:oVkZ8W8-Q8A
    [SysAbiExport(
        Nid = "oVkZ8W8-Q8A",
        ExportName = "strtok",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Compat_strtok(CpuContext ctx)
    {
        var input = ctx[CpuRegister.Rdi];
        var delimiters = ctx[CpuRegister.Rsi];
        var current = input != 0
            ? input
            : StrtokState.TryGetValue(ctx.Memory, out var saved)
                ? saved
                : 0;

        return StrtokCore(
            ctx,
            current,
            delimiters,
            next => StrtokState[ctx.Memory] = next);
    }
    // V46_EXPORT_END:oVkZ8W8-Q8A

}
