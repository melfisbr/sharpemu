// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers;
using SharpEmu.HLE;

namespace SharpEmu.Libs.LibcCompat;

public static class LibcMemoryStringExports
{
    // V35: bounded libc memory/string/wchar compatibility batch.
    private const int EINVAL = 22;
    private const int ERANGE = 34;
    private const ulong MaxCompatBytes = 64UL * 1024UL * 1024UL;
    private const ulong MaxCStringBytes = 4UL * 1024UL * 1024UL;
    private const ulong MaxWideChars = 1024UL * 1024UL;
    // V47: Orbis libc wide-character ABI uses 16-bit wchar_t units.
    private const ulong WideCharSize = sizeof(ushort);
    private static int _wideAbiTraceCount;

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
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int ReturnFloat(CpuContext ctx, float value)
    {
        ctx.SetXmmRegister(0, unchecked((uint)BitConverter.SingleToInt32Bits(value)), 0);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int ReturnInt(CpuContext ctx, int value)
    {
        ctx[CpuRegister.Rax] = unchecked((uint)value);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int ReturnLong(CpuContext ctx, long value)
    {
        ctx[CpuRegister.Rax] = unchecked((ulong)value);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int ReturnPointer(CpuContext ctx, ulong value)
    {
        ctx[CpuRegister.Rax] = value;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static double RoundForMxcsr(CpuContext ctx, double value)
    {
        if (!double.IsFinite(value)) return value;
        return ((ctx.Mxcsr >> 13) & 0x3) switch
        {
            0 => Math.Round(value, MidpointRounding.ToEven),
            1 => Math.Floor(value),
            2 => Math.Ceiling(value),
            _ => Math.Truncate(value),
        };
    }

    private static long ToInt64Compat(double value)
    {
        if (double.IsNaN(value)) return 0;
        if (value >= long.MaxValue) return long.MaxValue;
        if (value <= long.MinValue) return long.MinValue;
        return (long)value;
    }

    private static bool TryCStringLength(CpuContext ctx, ulong address, ulong limit, out ulong length)
    {
        length = 0;
        if (address == 0) return false;
        var max = Math.Min(limit, MaxCStringBytes);
        while (length < max)
        {
            if (!ctx.TryReadByte(address + length, out var b)) return false;
            if (b == 0) return true;
            length++;
        }
        return false;
    }

    private static bool TryWideLength(CpuContext ctx, ulong address, ulong limit, out ulong length)
    {
        length = 0;
        if (address == 0) return false;
        var max = Math.Min(limit, MaxWideChars);
        while (length < max)
        {
            if (!TryReadWideUnit(ctx, address + (length * WideCharSize), out var c)) return false;
            if (c == 0) return true;
            length++;
        }
        return false;
    }

    private static bool TryReadWideUnit(CpuContext ctx, ulong address, out uint value)
    {
        value = 0;
        if (!ctx.TryReadUInt16(address, out var unit)) return false;
        value = unit;
        return true;
    }

    private static bool TryWriteWideUnit(CpuContext ctx, ulong address, uint value) =>
        ctx.TryWriteUInt16(address, unchecked((ushort)value));

    private static void TraceWideAbi(
        CpuContext ctx,
        string operation,
        ulong first,
        ulong second,
        ulong count)
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_TRACE_WIDE_ABI"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        var index = System.Threading.Interlocked.Increment(ref _wideAbiTraceCount);
        if (index > 64) return;

        Console.Error.WriteLine(
            $"[LIBC-WIDE16][V47.0.1] #{index} op={operation} unit={WideCharSize} " +
            $"first=0x{first:X16} second=0x{second:X16} count={count} " +
            $"bytes={checked(count * WideCharSize)} rip=0x{ctx.Rip:X16}");
    }

    private static bool TryCopyBytes(CpuContext ctx, ulong destination, ulong source, ulong count)
    {
        if (count == 0) return true;
        if (destination == 0 || source == 0 || count > MaxCompatBytes || count > int.MaxValue) return false;
        var buffer = ArrayPool<byte>.Shared.Rent((int)count);
        try
        {
            var span = buffer.AsSpan(0, (int)count);
            return ctx.Memory.TryRead(source, span) && ctx.Memory.TryWrite(destination, span);
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }

    private static bool TryFillBytes(CpuContext ctx, ulong destination, byte value, ulong count)
    {
        if (count == 0) return true;
        if (destination == 0 || count > MaxCompatBytes) return false;
        var chunk = ArrayPool<byte>.Shared.Rent(64 * 1024);
        try
        {
            chunk.AsSpan(0, 64 * 1024).Fill(value);
            ulong done = 0;
            while (done < count)
            {
                var n = (int)Math.Min((ulong)(64 * 1024), count - done);
                if (!ctx.Memory.TryWrite(destination + done, chunk.AsSpan(0, n))) return false;
                done += (ulong)n;
            }
            return true;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(chunk);
        }
    }

    private static bool TryCopyWide(CpuContext ctx, ulong destination, ulong source, ulong count)
    {
        if (count == 0) return true;
        if (destination == 0 || source == 0 || count > MaxWideChars) return false;
        var bytes = checked(count * WideCharSize);
        return TryCopyBytes(ctx, destination, source, bytes);
    }

    private static int AsciiFold(byte value) =>
        value >= (byte)'A' && value <= (byte)'Z' ? value + ('a' - 'A') : value;

    [SysAbiExport(
        Nid = "Ye20uNnlglA",
        ExportName = "abs",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAbs(CpuContext ctx)
    {
        var value = unchecked((int)ctx[CpuRegister.Rdi]);
        var result = value == int.MinValue ? int.MinValue : Math.Abs(value);
        return ReturnInt(ctx, result);
    }

    [SysAbiExport(
        Nid = "xzZiQgReRGE",
        ExportName = "labs",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLabs(CpuContext ctx)
    {
        var value = unchecked((long)ctx[CpuRegister.Rdi]);
        var result = value == long.MinValue ? long.MinValue : Math.Abs(value);
        return ReturnLong(ctx, result);
    }

    [SysAbiExport(
        Nid = "rHRr+131ATY",
        ExportName = "llabs",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLlabs(CpuContext ctx)
    {
        var value = unchecked((long)ctx[CpuRegister.Rdi]);
        var result = value == long.MinValue ? long.MinValue : Math.Abs(value);
        return ReturnLong(ctx, result);
    }

    [SysAbiExport(
        Nid = "JrwFIMzKNr0",
        ExportName = "ldexp",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLdexp(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var exponent = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnDouble(ctx, Math.ScaleB(x, exponent));
    }

    [SysAbiExport(
        Nid = "KGKBeVcqJjc",
        ExportName = "scalbn",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatScalbn(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var exponent = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnDouble(ctx, Math.ScaleB(x, exponent));
    }

    [SysAbiExport(
        Nid = "kn0yiYeExgA",
        ExportName = "ldexpf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLdexpf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var exponent = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnFloat(ctx, (float)Math.ScaleB(x, exponent));
    }

    [SysAbiExport(
        Nid = "9fs1btfLoUs",
        ExportName = "scalbnf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatScalbnf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var exponent = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnFloat(ctx, (float)Math.ScaleB(x, exponent));
    }

    [SysAbiExport(
        Nid = "kA-TdiOCsaY",
        ExportName = "frexp",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFrexp(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var exponentAddress = ctx[CpuRegister.Rdi];
        int exponent = 0;
        double fraction = x;
        if (double.IsFinite(x) && x != 0)
        {
            exponent = Math.ILogB(Math.Abs(x)) + 1;
            fraction = Math.ScaleB(x, -exponent);
        }
        if (exponentAddress == 0 || !ctx.TryWriteInt32(exponentAddress, exponent))
        {
            ReturnDouble(ctx, fraction);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }
        return ReturnDouble(ctx, fraction);
    }

    [SysAbiExport(
        Nid = "aaDMGGkXFxo",
        ExportName = "frexpf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFrexpf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var exponentAddress = ctx[CpuRegister.Rdi];
        int exponent = 0;
        float fraction = x;
        if (float.IsFinite(x) && x != 0)
        {
            exponent = Math.ILogB(Math.Abs((double)x)) + 1;
            fraction = (float)Math.ScaleB(x, -exponent);
        }
        if (exponentAddress == 0 || !ctx.TryWriteInt32(exponentAddress, exponent))
        {
            ReturnFloat(ctx, fraction);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }
        return ReturnFloat(ctx, fraction);
    }

    [SysAbiExport(
        Nid = "0WMHDb5Dt94",
        ExportName = "modf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatModf(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var integralAddress = ctx[CpuRegister.Rdi];
        double integral;
        double fraction;
        if (double.IsNaN(x))
        {
            integral = double.NaN;
            fraction = double.NaN;
        }
        else if (double.IsInfinity(x))
        {
            integral = x;
            fraction = BitConverter.Int64BitsToDouble(
                unchecked((long)(unchecked((ulong)BitConverter.DoubleToInt64Bits(x)) & 0x8000_0000_0000_0000UL)));
        }
        else
        {
            integral = Math.Truncate(x);
            fraction = x - integral;
            if (fraction == 0)
            {
                fraction = BitConverter.Int64BitsToDouble(
                    unchecked((long)(unchecked((ulong)BitConverter.DoubleToInt64Bits(x)) & 0x8000_0000_0000_0000UL)));
            }
        }
        if (integralAddress == 0 ||
            !ctx.TryWriteUInt64(integralAddress, unchecked((ulong)BitConverter.DoubleToInt64Bits(integral))))
        {
            ReturnDouble(ctx, fraction);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }
        return ReturnDouble(ctx, fraction);
    }

    [SysAbiExport(
        Nid = "3+UPM-9E6xY",
        ExportName = "modff",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatModff(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var integralAddress = ctx[CpuRegister.Rdi];
        float integral;
        float fraction;
        if (float.IsNaN(x))
        {
            integral = float.NaN;
            fraction = float.NaN;
        }
        else if (float.IsInfinity(x))
        {
            integral = x;
            fraction = BitConverter.Int32BitsToSingle(
                unchecked((int)(unchecked((uint)BitConverter.SingleToInt32Bits(x)) & 0x8000_0000U)));
        }
        else
        {
            integral = MathF.Truncate(x);
            fraction = x - integral;
            if (fraction == 0)
            {
                fraction = BitConverter.Int32BitsToSingle(
                    unchecked((int)(unchecked((uint)BitConverter.SingleToInt32Bits(x)) & 0x8000_0000U)));
            }
        }
        if (integralAddress == 0 ||
            !ctx.TryWriteInt32(integralAddress, BitConverter.SingleToInt32Bits(integral)))
        {
            ReturnFloat(ctx, fraction);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }
        return ReturnFloat(ctx, fraction);
    }

    [SysAbiExport(
        Nid = "J3XuGS-cC0Q",
        ExportName = "lround",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLround(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var rounded = Math.Round(x, MidpointRounding.AwayFromZero);
        return ReturnLong(ctx, ToInt64Compat(rounded));
    }

    [SysAbiExport(
        Nid = "w-BvXF4O6xo",
        ExportName = "llround",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLlround(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var rounded = Math.Round(x, MidpointRounding.AwayFromZero);
        return ReturnLong(ctx, ToInt64Compat(rounded));
    }

    [SysAbiExport(
        Nid = "C6gWCWJKM+U",
        ExportName = "lroundf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLroundf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var rounded = Math.Round(x, MidpointRounding.AwayFromZero);
        return ReturnLong(ctx, ToInt64Compat(rounded));
    }

    [SysAbiExport(
        Nid = "eQhBFnTOp40",
        ExportName = "llroundf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLlroundf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var rounded = Math.Round(x, MidpointRounding.AwayFromZero);
        return ReturnLong(ctx, ToInt64Compat(rounded));
    }

    [SysAbiExport(
        Nid = "VOKOgR7L-2Y",
        ExportName = "lrint",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLrint(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnLong(ctx, ToInt64Compat(RoundForMxcsr(ctx, x)));
    }

    [SysAbiExport(
        Nid = "-431A-YBAks",
        ExportName = "llrint",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLlrint(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnLong(ctx, ToInt64Compat(RoundForMxcsr(ctx, x)));
    }

    [SysAbiExport(
        Nid = "rcVv5ivMhY0",
        ExportName = "lrintf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLrintf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnLong(ctx, ToInt64Compat(RoundForMxcsr(ctx, x)));
    }

    [SysAbiExport(
        Nid = "KPsQA0pis8o",
        ExportName = "llrintf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLlrintf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnLong(ctx, ToInt64Compat(RoundForMxcsr(ctx, x)));
    }

    [SysAbiExport(
        Nid = "NFLs+dRJGNg",
        ExportName = "memcpy_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatMemcpys(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationSize = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        var count = ctx[CpuRegister.Rcx];

        if (destination == 0 || destinationSize > MaxCompatBytes)
            return ReturnInt(ctx, EINVAL);
        if (count > destinationSize || count > MaxCompatBytes)
        {
            _ = TryFillBytes(ctx, destination, 0, destinationSize);
            return ReturnInt(ctx, ERANGE);
        }
        if (count != 0 && source == 0)
        {
            _ = TryFillBytes(ctx, destination, 0, destinationSize);
            return ReturnInt(ctx, EINVAL);
        }
        if (!TryCopyBytes(ctx, destination, source, count))
        {
            _ = TryFillBytes(ctx, destination, 0, destinationSize);
            return ReturnInt(ctx, EINVAL);
        }
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "B59+zQQCcbU",
        ExportName = "memmove_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatMemmoves(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationSize = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        var count = ctx[CpuRegister.Rcx];

        if (destination == 0 || destinationSize > MaxCompatBytes)
            return ReturnInt(ctx, EINVAL);
        if (count > destinationSize || count > MaxCompatBytes)
        {
            _ = TryFillBytes(ctx, destination, 0, destinationSize);
            return ReturnInt(ctx, ERANGE);
        }
        if (count != 0 && source == 0)
        {
            _ = TryFillBytes(ctx, destination, 0, destinationSize);
            return ReturnInt(ctx, EINVAL);
        }
        if (!TryCopyBytes(ctx, destination, source, count))
        {
            _ = TryFillBytes(ctx, destination, 0, destinationSize);
            return ReturnInt(ctx, EINVAL);
        }
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "h8GwqPFbu6I",
        ExportName = "memset_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatMemsets(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationSize = ctx[CpuRegister.Rsi];
        var value = unchecked((byte)ctx[CpuRegister.Rdx]);
        var count = ctx[CpuRegister.Rcx];
        if (destination == 0 || count > destinationSize || destinationSize > MaxCompatBytes)
            return ReturnInt(ctx, EINVAL);
        return ReturnInt(ctx, TryFillBytes(ctx, destination, value, count) ? 0 : EINVAL);
    }

    [SysAbiExport(
        Nid = "q0F6yS-rCms",
        ExportName = "strcspn",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrcspn(CpuContext ctx)
    {
        var stringAddress = ctx[CpuRegister.Rdi];
        var setAddress = ctx[CpuRegister.Rsi];
        if (!TryCStringLength(ctx, stringAddress, MaxCStringBytes, out var stringLength) ||
            !TryCStringLength(ctx, setAddress, MaxCStringBytes, out var setLength))
            return ReturnLong(ctx, 0);
        ulong count = 0;
        while (count < stringLength)
        {
            if (!ctx.TryReadByte(stringAddress + count, out var b)) break;
            var inSet = false;
            for (ulong j = 0; j < setLength; j++)
            {
                if (!ctx.TryReadByte(setAddress + j, out var sb)) return ReturnLong(ctx, 0);
                if (sb == b) { inSet = true; break; }
            }
            if (inSet) break;
            count++;
        }
        return ReturnLong(ctx, unchecked((long)count));
    }

    [SysAbiExport(
        Nid = "-kU6bB4M-+k",
        ExportName = "strspn",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrspn(CpuContext ctx)
    {
        var stringAddress = ctx[CpuRegister.Rdi];
        var setAddress = ctx[CpuRegister.Rsi];
        if (!TryCStringLength(ctx, stringAddress, MaxCStringBytes, out var stringLength) ||
            !TryCStringLength(ctx, setAddress, MaxCStringBytes, out var setLength))
            return ReturnLong(ctx, 0);
        ulong count = 0;
        while (count < stringLength)
        {
            if (!ctx.TryReadByte(stringAddress + count, out var b)) break;
            var inSet = false;
            for (ulong j = 0; j < setLength; j++)
            {
                if (!ctx.TryReadByte(setAddress + j, out var sb)) return ReturnLong(ctx, 0);
                if (sb == b) { inSet = true; break; }
            }
            if (!inSet) break;
            count++;
        }
        return ReturnLong(ctx, unchecked((long)count));
    }

    [SysAbiExport(
        Nid = "kDZvoVssCgQ",
        ExportName = "strpbrk",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrpbrk(CpuContext ctx)
    {
        var stringAddress = ctx[CpuRegister.Rdi];
        var setAddress = ctx[CpuRegister.Rsi];
        if (!TryCStringLength(ctx, stringAddress, MaxCStringBytes, out var stringLength) ||
            !TryCStringLength(ctx, setAddress, MaxCStringBytes, out var setLength))
            return ReturnPointer(ctx, 0);
        for (ulong i = 0; i < stringLength; i++)
        {
            if (!ctx.TryReadByte(stringAddress + i, out var b)) return ReturnPointer(ctx, 0);
            for (ulong j = 0; j < setLength; j++)
            {
                if (!ctx.TryReadByte(setAddress + j, out var sb)) return ReturnPointer(ctx, 0);
                if (b == sb) return ReturnPointer(ctx, stringAddress + i);
            }
        }
        return ReturnPointer(ctx, 0);
    }

    [SysAbiExport(
        Nid = "DQbtGaBKlaw",
        ExportName = "strnlen_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrnlens(CpuContext ctx)
    {
        var address = ctx[CpuRegister.Rdi];
        var max = ctx[CpuRegister.Rsi];
        if (address == 0) return ReturnLong(ctx, 0);
        var limit = Math.Min(max, MaxCStringBytes);
        ulong length = 0;
        while (length < limit)
        {
            if (!ctx.TryReadByte(address + length, out var b)) return ReturnLong(ctx, 0);
            if (b == 0) break;
            length++;
        }
        return ReturnLong(ctx, unchecked((long)length));
    }

    [SysAbiExport(
        Nid = "pXvbDfchu6k",
        ExportName = "strncasecmp",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrncasecmp(CpuContext ctx)
    {
        var left = ctx[CpuRegister.Rdi];
        var right = ctx[CpuRegister.Rsi];
        var count = Math.Min(ctx[CpuRegister.Rdx], MaxCStringBytes);
        if (count == 0) return ReturnInt(ctx, 0);
        if (left == 0 || right == 0) return ReturnInt(ctx, left == right ? 0 : (left == 0 ? -1 : 1));
        for (ulong i = 0; i < count; i++)
        {
            if (!ctx.TryReadByte(left + i, out var a) || !ctx.TryReadByte(right + i, out var b))
                return ReturnInt(ctx, 0);
            var fa = AsciiFold(a);
            var fb = AsciiFold(b);
            if (fa != fb) return ReturnInt(ctx, fa < fb ? -1 : 1);
            if (a == 0 || b == 0) return ReturnInt(ctx, 0);
        }
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "SfQIZcqvvms",
        ExportName = "strlcpy",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrlcpy(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var source = ctx[CpuRegister.Rsi];
        var size = ctx[CpuRegister.Rdx];
        if (!TryCStringLength(ctx, source, MaxCStringBytes, out var sourceLength))
            return ReturnLong(ctx, 0);
        if (size != 0 && destination != 0)
        {
            var copy = Math.Min(sourceLength, size - 1);
            if (copy != 0 && !TryCopyBytes(ctx, destination, source, copy)) return ReturnLong(ctx, 0);
            if (!ctx.Memory.TryWrite(destination + copy, new byte[] { 0 })) return ReturnLong(ctx, 0);
        }
        return ReturnLong(ctx, unchecked((long)sourceLength));
    }

    [SysAbiExport(
        Nid = "ByfjUZsWiyg",
        ExportName = "strlcat",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrlcat(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var source = ctx[CpuRegister.Rsi];
        var size = ctx[CpuRegister.Rdx];
        if (!TryCStringLength(ctx, source, MaxCStringBytes, out var sourceLength))
            return ReturnLong(ctx, 0);

        ulong destLength = 0;
        var destTerminated = destination != 0 && TryCStringLength(ctx, destination, size, out destLength);
        if (!destTerminated)
            return ReturnLong(ctx, unchecked((long)(size + sourceLength)));

        if (destLength < size)
        {
            var available = size - destLength - 1;
            var copy = Math.Min(sourceLength, available);
            if (copy != 0 && !TryCopyBytes(ctx, destination + destLength, source, copy))
                return ReturnLong(ctx, 0);
            if (!ctx.Memory.TryWrite(destination + destLength + copy, new byte[] { 0 }))
                return ReturnLong(ctx, 0);
        }
        return ReturnLong(ctx, unchecked((long)(destLength + sourceLength)));
    }

    [SysAbiExport(
        Nid = "5Xa2ACNECdo",
        ExportName = "strcpy_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrcpys(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationSize = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        if (destination == 0 || destinationSize == 0 || destinationSize > MaxCompatBytes || source == 0)
            return ReturnInt(ctx, EINVAL);
        if (!TryCStringLength(ctx, source, MaxCStringBytes, out var length) || length + 1 > destinationSize)
        {
            _ = TryFillBytes(ctx, destination, 0, Math.Min(destinationSize, MaxCompatBytes));
            return ReturnInt(ctx, ERANGE);
        }
        if (!TryCopyBytes(ctx, destination, source, length + 1))
            return ReturnInt(ctx, EINVAL);
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "K+gcnFFJKVc",
        ExportName = "strcat_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrcats(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationSize = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        if (destination == 0 || destinationSize == 0 || destinationSize > MaxCompatBytes || source == 0)
            return ReturnInt(ctx, EINVAL);
        if (!TryCStringLength(ctx, destination, destinationSize, out var destLength) ||
            !TryCStringLength(ctx, source, MaxCStringBytes, out var sourceLength) ||
            destLength + sourceLength + 1 > destinationSize)
        {
            _ = TryFillBytes(ctx, destination, 0, Math.Min(destinationSize, MaxCompatBytes));
            return ReturnInt(ctx, ERANGE);
        }
        if (!TryCopyBytes(ctx, destination + destLength, source, sourceLength + 1))
            return ReturnInt(ctx, EINVAL);
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "YNzNkJzYqEg",
        ExportName = "strncpy_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrncpys(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationSize = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        var count = ctx[CpuRegister.Rcx];
        if (destination == 0 || destinationSize == 0 || destinationSize > MaxCompatBytes || source == 0)
            return ReturnInt(ctx, EINVAL);
        if (!TryCStringLength(ctx, source, MaxCStringBytes, out var sourceLength))
            return ReturnInt(ctx, EINVAL);

        var requested = count == ulong.MaxValue ? sourceLength : Math.Min(sourceLength, count);
        if (requested + 1 > destinationSize)
        {
            if (count == ulong.MaxValue)
                requested = destinationSize - 1;
            else
            {
                _ = TryFillBytes(ctx, destination, 0, destinationSize);
                return ReturnInt(ctx, ERANGE);
            }
        }
        if (requested != 0 && !TryCopyBytes(ctx, destination, source, requested))
            return ReturnInt(ctx, EINVAL);
        if (!ctx.Memory.TryWrite(destination + requested, new byte[] { 0 }))
            return ReturnInt(ctx, EINVAL);
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "NC4MSB+BRQg",
        ExportName = "strncat_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatStrncats(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationSize = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        var count = ctx[CpuRegister.Rcx];
        if (destination == 0 || destinationSize == 0 || destinationSize > MaxCompatBytes || source == 0)
            return ReturnInt(ctx, EINVAL);
        if (!TryCStringLength(ctx, destination, destinationSize, out var destLength) ||
            !TryCStringLength(ctx, source, MaxCStringBytes, out var sourceLength))
            return ReturnInt(ctx, EINVAL);

        var requested = count == ulong.MaxValue ? sourceLength : Math.Min(sourceLength, count);
        if (destLength + requested + 1 > destinationSize)
        {
            if (count == ulong.MaxValue)
                requested = destinationSize > destLength ? destinationSize - destLength - 1 : 0;
            else
            {
                _ = TryFillBytes(ctx, destination, 0, destinationSize);
                return ReturnInt(ctx, ERANGE);
            }
        }
        if (requested != 0 && !TryCopyBytes(ctx, destination + destLength, source, requested))
            return ReturnInt(ctx, EINVAL);
        if (!ctx.Memory.TryWrite(destination + destLength + requested, new byte[] { 0 }))
            return ReturnInt(ctx, EINVAL);
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "K+v+cnmGoH4",
        ExportName = "wcsnlen_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcsnlens(CpuContext ctx)
    {
        var address = ctx[CpuRegister.Rdi];
        var max = Math.Min(ctx[CpuRegister.Rsi], MaxWideChars);
        if (address == 0) return ReturnLong(ctx, 0);
        ulong length = 0;
        while (length < max)
        {
            if (!TryReadWideUnit(ctx, address + length * WideCharSize, out var c)) return ReturnLong(ctx, 0);
            if (c == 0) break;
            length++;
        }
        return ReturnLong(ctx, unchecked((long)length));
    }

    [SysAbiExport(
        Nid = "x9uumWcxhXU",
        ExportName = "wcsspn",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcsspn(CpuContext ctx)
    {
        var text = ctx[CpuRegister.Rdi];
        var set = ctx[CpuRegister.Rsi];
        if (!TryWideLength(ctx, text, MaxWideChars, out var textLength) ||
            !TryWideLength(ctx, set, MaxWideChars, out var setLength))
            return ReturnLong(ctx, 0);
        ulong count = 0;
        while (count < textLength)
        {
            if (!TryReadWideUnit(ctx, text + count * WideCharSize, out var c)) break;
            var inSet = false;
            for (ulong j = 0; j < setLength; j++)
            {
                if (!TryReadWideUnit(ctx, set + j * WideCharSize, out var s)) break;
                if (c == s) { inSet = true; break; }
            }
            if (!inSet) break;
            count++;
        }
        return ReturnLong(ctx, unchecked((long)count));
    }

    [SysAbiExport(
        Nid = "7eNus40aGuk",
        ExportName = "wcscspn",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcscspn(CpuContext ctx)
    {
        var text = ctx[CpuRegister.Rdi];
        var set = ctx[CpuRegister.Rsi];
        if (!TryWideLength(ctx, text, MaxWideChars, out var textLength) ||
            !TryWideLength(ctx, set, MaxWideChars, out var setLength))
            return ReturnLong(ctx, 0);
        ulong count = 0;
        while (count < textLength)
        {
            if (!TryReadWideUnit(ctx, text + count * WideCharSize, out var c)) break;
            var inSet = false;
            for (ulong j = 0; j < setLength; j++)
            {
                if (!TryReadWideUnit(ctx, set + j * WideCharSize, out var s)) break;
                if (c == s) { inSet = true; break; }
            }
            if (inSet) break;
            count++;
        }
        return ReturnLong(ctx, unchecked((long)count));
    }

    [SysAbiExport(
        Nid = "H4MCONF+Gps",
        ExportName = "wcspbrk",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcspbrk(CpuContext ctx)
    {
        var text = ctx[CpuRegister.Rdi];
        var set = ctx[CpuRegister.Rsi];
        if (!TryWideLength(ctx, text, MaxWideChars, out var textLength) ||
            !TryWideLength(ctx, set, MaxWideChars, out var setLength))
            return ReturnPointer(ctx, 0);
        for (ulong i = 0; i < textLength; i++)
        {
            if (!TryReadWideUnit(ctx, text + i * WideCharSize, out var c)) return ReturnPointer(ctx, 0);
            for (ulong j = 0; j < setLength; j++)
            {
                if (!TryReadWideUnit(ctx, set + j * WideCharSize, out var s)) return ReturnPointer(ctx, 0);
                if (c == s) return ReturnPointer(ctx, text + i * WideCharSize);
            }
        }
        return ReturnPointer(ctx, 0);
    }

    [SysAbiExport(
        Nid = "g3ShSirD50I",
        ExportName = "wcsrchr",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcsrchr(CpuContext ctx)
    {
        var text = ctx[CpuRegister.Rdi];
        var needle = unchecked((uint)ctx[CpuRegister.Rsi]);
        if (!TryWideLength(ctx, text, MaxWideChars, out var length))
            return ReturnPointer(ctx, 0);
        ulong result = 0;
        for (ulong i = 0; i <= length; i++)
        {
            if (!TryReadWideUnit(ctx, text + i * WideCharSize, out var c)) break;
            if (c == needle) result = text + i * WideCharSize;
        }
        return ReturnPointer(ctx, result);
    }

    [SysAbiExport(
        Nid = "WDpobjImAb4",
        ExportName = "wcsstr",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcsstr(CpuContext ctx)
    {
        var haystack = ctx[CpuRegister.Rdi];
        var needle = ctx[CpuRegister.Rsi];
        if (!TryWideLength(ctx, haystack, MaxWideChars, out var hlen) ||
            !TryWideLength(ctx, needle, MaxWideChars, out var nlen))
            return ReturnPointer(ctx, 0);
        if (nlen == 0) return ReturnPointer(ctx, haystack);
        if (nlen > hlen) return ReturnPointer(ctx, 0);
        for (ulong i = 0; i <= hlen - nlen; i++)
        {
            var match = true;
            for (ulong j = 0; j < nlen; j++)
            {
                if (!TryReadWideUnit(ctx, haystack + (i + j) * WideCharSize, out var a) ||
                    !TryReadWideUnit(ctx, needle + j * WideCharSize, out var b) || a != b)
                {
                    match = false;
                    break;
                }
            }
            if (match) return ReturnPointer(ctx, haystack + i * WideCharSize);
        }
        return ReturnPointer(ctx, 0);
    }

    [SysAbiExport(
        Nid = "KZm8HUIX2Rw",
        ExportName = "wcscat",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcscat(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var source = ctx[CpuRegister.Rsi];
        if (!TryWideLength(ctx, destination, MaxWideChars, out var destLength) ||
            !TryWideLength(ctx, source, MaxWideChars, out var sourceLength))
            return ReturnPointer(ctx, 0);
        if (!TryCopyWide(ctx, destination + destLength * WideCharSize, source, sourceLength + 1))
            return ReturnPointer(ctx, 0);
        return ReturnPointer(ctx, destination);
    }

    [SysAbiExport(
        Nid = "pA9N3VIgEZ4",
        ExportName = "wcsncat",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWcsncat(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var source = ctx[CpuRegister.Rsi];
        var count = Math.Min(ctx[CpuRegister.Rdx], MaxWideChars);
        if (!TryWideLength(ctx, destination, MaxWideChars, out var destLength) ||
            !TryWideLength(ctx, source, MaxWideChars, out var sourceLength))
            return ReturnPointer(ctx, 0);
        var copy = Math.Min(sourceLength, count);
        if (copy != 0 && !TryCopyWide(ctx, destination + destLength * WideCharSize, source, copy))
            return ReturnPointer(ctx, 0);
        if (!TryWriteWideUnit(ctx, destination + (destLength + copy) * WideCharSize, 0))
            return ReturnPointer(ctx, 0);
        return ReturnPointer(ctx, destination);
    }

    [SysAbiExport(
        Nid = "fnUEjBCNRVU",
        ExportName = "wmemchr",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWmemchr(CpuContext ctx)
    {
        var address = ctx[CpuRegister.Rdi];
        var value = unchecked((uint)ctx[CpuRegister.Rsi]);
        var count = Math.Min(ctx[CpuRegister.Rdx], MaxWideChars);
        for (ulong i = 0; i < count; i++)
        {
            if (!TryReadWideUnit(ctx, address + i * WideCharSize, out var c)) return ReturnPointer(ctx, 0);
            if (c == value) return ReturnPointer(ctx, address + i * WideCharSize);
        }
        return ReturnPointer(ctx, 0);
    }

    [SysAbiExport(
        Nid = "QJ5xVfKkni0",
        ExportName = "wmemcmp",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWmemcmp(CpuContext ctx)
    {
        var left = ctx[CpuRegister.Rdi];
        var right = ctx[CpuRegister.Rsi];
        var count = Math.Min(ctx[CpuRegister.Rdx], MaxWideChars);
        TraceWideAbi(ctx, "wmemcmp", left, right, count);
        for (ulong i = 0; i < count; i++)
        {
            if (!TryReadWideUnit(ctx, left + i * WideCharSize, out var a) ||
                !TryReadWideUnit(ctx, right + i * WideCharSize, out var b))
                return ReturnInt(ctx, 0);
            if (a != b) return ReturnInt(ctx, a < b ? -1 : 1);
        }
        return ReturnInt(ctx, 0);
    }

    [SysAbiExport(
        Nid = "fL3O02ypZFE",
        ExportName = "wmemcpy",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWmemcpy(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var source = ctx[CpuRegister.Rsi];
        var count = ctx[CpuRegister.Rdx];
        TraceWideAbi(ctx, "wmemcpy", destination, source, count);
        return ReturnPointer(ctx, TryCopyWide(ctx, destination, source, count) ? destination : 0);
    }

    [SysAbiExport(
        Nid = "Noj9PsJrsa8",
        ExportName = "wmemmove",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWmemmove(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var source = ctx[CpuRegister.Rsi];
        var count = ctx[CpuRegister.Rdx];
        TraceWideAbi(ctx, "wmemmove", destination, source, count);
        return ReturnPointer(ctx, TryCopyWide(ctx, destination, source, count) ? destination : 0);
    }

    [SysAbiExport(
        Nid = "Al8MZJh-4hM",
        ExportName = "wmemset",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWmemset(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var value = unchecked((uint)ctx[CpuRegister.Rsi]);
        var count = Math.Min(ctx[CpuRegister.Rdx], MaxWideChars);
        TraceWideAbi(ctx, "wmemset", destination, value, count);
        if (destination == 0) return ReturnPointer(ctx, 0);
        for (ulong i = 0; i < count; i++)
        {
            if (!TryWriteWideUnit(ctx, destination + i * WideCharSize, value)) return ReturnPointer(ctx, 0);
        }
        return ReturnPointer(ctx, destination);
    }

    [SysAbiExport(
        Nid = "BTsuaJ6FxKM",
        ExportName = "wmemcpy_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWmemcpys(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationCount = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        var count = ctx[CpuRegister.Rcx];
        if (destination == 0 || destinationCount > MaxWideChars)
            return ReturnInt(ctx, EINVAL);
        if (count > destinationCount || count > MaxWideChars)
        {
            for (ulong i = 0; i < Math.Min(destinationCount, MaxWideChars); i++)
                _ = TryWriteWideUnit(ctx, destination + i * WideCharSize, 0);
            return ReturnInt(ctx, ERANGE);
        }
        if (count != 0 && source == 0)
            return ReturnInt(ctx, EINVAL);
        return ReturnInt(ctx, TryCopyWide(ctx, destination, source, count) ? 0 : EINVAL);
    }

    [SysAbiExport(
        Nid = "F8b+Wb-YQVs",
        ExportName = "wmemmove_s",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatWmemmoves(CpuContext ctx)
    {
        var destination = ctx[CpuRegister.Rdi];
        var destinationCount = ctx[CpuRegister.Rsi];
        var source = ctx[CpuRegister.Rdx];
        var count = ctx[CpuRegister.Rcx];
        if (destination == 0 || destinationCount > MaxWideChars)
            return ReturnInt(ctx, EINVAL);
        if (count > destinationCount || count > MaxWideChars)
        {
            for (ulong i = 0; i < Math.Min(destinationCount, MaxWideChars); i++)
                _ = TryWriteWideUnit(ctx, destination + i * WideCharSize, 0);
            return ReturnInt(ctx, ERANGE);
        }
        if (count != 0 && source == 0)
            return ReturnInt(ctx, EINVAL);
        return ReturnInt(ctx, TryCopyWide(ctx, destination, source, count) ? 0 : EINVAL);
    }

}
