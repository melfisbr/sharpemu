// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Numerics;
using SharpEmu.HLE;

namespace SharpEmu.Libs.LibcCompat;

/// <summary>
/// V34 deterministic libc/libm/compiler-runtime compatibility exports.
///
/// These handlers implement ABI-stable scalar operations only. They deliberately
/// do not fabricate locale databases, host callbacks, PS5 services, errno side
/// effects, or floating-point exception flags that are not represented by CpuContext.
/// </summary>
public static class LibcMathCompilerRuntimeExports
{
    // V34: deterministic libc/libm/compiler-runtime API batch.

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

    private static int ReturnUInt64(CpuContext ctx, ulong value)
    {
        ctx[CpuRegister.Rax] = value;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static double RoundForMxcsr(CpuContext ctx, double value)
    {
        if (!double.IsFinite(value))
        {
            return value;
        }

        return ((ctx.Mxcsr >> 13) & 0x3) switch
        {
            0 => Math.Round(value, MidpointRounding.ToEven),
            1 => Math.Floor(value),
            2 => Math.Ceiling(value),
            _ => Math.Truncate(value),
        };
    }

    private static float RoundForMxcsr(CpuContext ctx, float value)
    {
        if (!float.IsFinite(value))
        {
            return value;
        }

        return ((ctx.Mxcsr >> 13) & 0x3) switch
        {
            0 => MathF.Round(value, MidpointRounding.ToEven),
            1 => MathF.Floor(value),
            2 => MathF.Ceiling(value),
            _ => MathF.Truncate(value),
        };
    }

    private static double Hypot(double x, double y)
    {
        x = Math.Abs(x);
        y = Math.Abs(y);
        if (double.IsInfinity(x) || double.IsInfinity(y))
        {
            return double.PositiveInfinity;
        }
        if (double.IsNaN(x) || double.IsNaN(y))
        {
            return double.NaN;
        }

        var max = Math.Max(x, y);
        var min = Math.Min(x, y);
        if (max == 0)
        {
            return 0;
        }

        var ratio = min / max;
        return max * Math.Sqrt(1 + (ratio * ratio));
    }

    private static double FMin(double x, double y)
    {
        if (double.IsNaN(x)) return y;
        if (double.IsNaN(y)) return x;
        if (x == 0 && y == 0)
        {
            // fmin(-0,+0) must prefer -0.
            var xb = unchecked((ulong)BitConverter.DoubleToInt64Bits(x));
            var yb = unchecked((ulong)BitConverter.DoubleToInt64Bits(y));
            return (xb >> 63) != 0 || (yb >> 63) != 0 ? -0.0 : 0.0;
        }
        return x < y ? x : y;
    }

    private static double FMax(double x, double y)
    {
        if (double.IsNaN(x)) return y;
        if (double.IsNaN(y)) return x;
        if (x == 0 && y == 0)
        {
            // fmax(-0,+0) must prefer +0.
            var xb = unchecked((ulong)BitConverter.DoubleToInt64Bits(x));
            var yb = unchecked((ulong)BitConverter.DoubleToInt64Bits(y));
            return (xb >> 63) == 0 || (yb >> 63) == 0 ? 0.0 : -0.0;
        }
        return x > y ? x : y;
    }

    private static float FMin(float x, float y)
    {
        if (float.IsNaN(x)) return y;
        if (float.IsNaN(y)) return x;
        if (x == 0 && y == 0)
        {
            var xb = unchecked((uint)BitConverter.SingleToInt32Bits(x));
            var yb = unchecked((uint)BitConverter.SingleToInt32Bits(y));
            return (xb >> 31) != 0 || (yb >> 31) != 0 ? -0.0f : 0.0f;
        }
        return x < y ? x : y;
    }

    private static float FMax(float x, float y)
    {
        if (float.IsNaN(x)) return y;
        if (float.IsNaN(y)) return x;
        if (x == 0 && y == 0)
        {
            var xb = unchecked((uint)BitConverter.SingleToInt32Bits(x));
            var yb = unchecked((uint)BitConverter.SingleToInt32Bits(y));
            return (xb >> 31) == 0 || (yb >> 31) == 0 ? 0.0f : -0.0f;
        }
        return x > y ? x : y;
    }

    private static double CopySign(double magnitude, double sign)
    {
        var magBits = unchecked((ulong)BitConverter.DoubleToInt64Bits(magnitude)) & 0x7FFF_FFFF_FFFF_FFFFUL;
        var signBits = unchecked((ulong)BitConverter.DoubleToInt64Bits(sign)) & 0x8000_0000_0000_0000UL;
        return BitConverter.Int64BitsToDouble(unchecked((long)(magBits | signBits)));
    }

    private static float CopySign(float magnitude, float sign)
    {
        var magBits = unchecked((uint)BitConverter.SingleToInt32Bits(magnitude)) & 0x7FFF_FFFFU;
        var signBits = unchecked((uint)BitConverter.SingleToInt32Bits(sign)) & 0x8000_0000U;
        return BitConverter.Int32BitsToSingle(unchecked((int)(magBits | signBits)));
    }

    private static int ComputeRemQuo(double x, double y, out double remainder)
    {
        remainder = Math.IEEERemainder(x, y);
        if (!double.IsFinite(x) || !double.IsFinite(y) || y == 0 || double.IsNaN(remainder))
        {
            return 0;
        }

        var q = Math.Round(x / y, MidpointRounding.ToEven);
        if (!double.IsFinite(q))
        {
            return 0;
        }

        var absLowBits = (int)(Math.Abs(q) % 8.0);
        return q < 0 ? -absLowBits : absLowBits;
    }

    private static bool IsAsciiUpper(int c) => c >= 'A' && c <= 'Z';
    private static bool IsAsciiLower(int c) => c >= 'a' && c <= 'z';
    private static bool IsAsciiDigit(int c) => c >= '0' && c <= '9';
    private static bool IsAsciiXDigit(int c) =>
        IsAsciiDigit(c) || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
    private static bool IsAsciiAlpha(int c) => IsAsciiUpper(c) || IsAsciiLower(c);
    private static bool IsAsciiAlnum(int c) => IsAsciiAlpha(c) || IsAsciiDigit(c);
    private static bool IsAsciiSpace(int c) => c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
    private static bool IsAsciiControl(int c) => (c >= 0 && c < 0x20) || c == 0x7F;
    private static bool IsAsciiPrint(int c) => c >= 0x20 && c <= 0x7E;
    private static bool IsAsciiGraph(int c) => c >= 0x21 && c <= 0x7E;
    private static bool IsAsciiPunct(int c) => IsAsciiGraph(c) && !IsAsciiAlnum(c);

    [SysAbiExport(
        Nid = "H8ya2H00jbI",
        ExportName = "sin",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatSin(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Sin(x));
    }

    [SysAbiExport(
        Nid = "2WE3BTYVwKM",
        ExportName = "cos",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCos(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Cos(x));
    }

    [SysAbiExport(
        Nid = "T7uyNqP7vQA",
        ExportName = "tan",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTan(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Tan(x));
    }

    [SysAbiExport(
        Nid = "7Ly52zaL44Q",
        ExportName = "asin",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAsin(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Asin(x));
    }

    [SysAbiExport(
        Nid = "JBcgYuW8lPU",
        ExportName = "acos",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAcos(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Acos(x));
    }

    [SysAbiExport(
        Nid = "OXmauLdQ8kY",
        ExportName = "atan",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAtan(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Atan(x));
    }

    [SysAbiExport(
        Nid = "ZjtRqSMJwdw",
        ExportName = "sinh",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatSinh(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Sinh(x));
    }

    [SysAbiExport(
        Nid = "m7iLTaO9RMs",
        ExportName = "cosh",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCosh(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Cosh(x));
    }

    [SysAbiExport(
        Nid = "JM4EBvWT9rc",
        ExportName = "tanh",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTanh(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Tanh(x));
    }

    [SysAbiExport(
        Nid = "NVadfnzQhHQ",
        ExportName = "exp",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatExp(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Exp(x));
    }

    [SysAbiExport(
        Nid = "dnaeGXbjP6E",
        ExportName = "exp2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatExp2(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Pow(2.0, x));
    }

    [SysAbiExport(
        Nid = "rtV7-jWC6Yg",
        ExportName = "log",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLog(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Log(x));
    }

    [SysAbiExport(
        Nid = "Y5DhuDKGlnQ",
        ExportName = "log2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLog2(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Log2(x));
    }

    [SysAbiExport(
        Nid = "WuMbPBKN1TU",
        ExportName = "log10",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLog10(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Log10(x));
    }

    [SysAbiExport(
        Nid = "MXRNWnosNlM",
        ExportName = "sqrt",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatSqrt(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Sqrt(x));
    }

    [SysAbiExport(
        Nid = "5ZkEP3Rq7As",
        ExportName = "cbrt",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCbrt(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Cbrt(x));
    }

    [SysAbiExport(
        Nid = "gacfOmO8hNs",
        ExportName = "ceil",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCeil(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Ceiling(x));
    }

    [SysAbiExport(
        Nid = "mpcTgMzhUY8",
        ExportName = "floor",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFloor(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Floor(x));
    }

    [SysAbiExport(
        Nid = "a4gLGspPEDM",
        ExportName = "trunc",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTrunc(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Truncate(x));
    }

    [SysAbiExport(
        Nid = "nlaojL9hDtA",
        ExportName = "round",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRound(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Round(x, MidpointRounding.AwayFromZero));
    }

    [SysAbiExport(
        Nid = "LxGIYYKwKYc",
        ExportName = "rint",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRint(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, RoundForMxcsr(ctx, x));
    }

    [SysAbiExport(
        Nid = "cJLTwtKGXJk",
        ExportName = "nearbyint",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatNearbyint(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, RoundForMxcsr(ctx, x));
    }

    [SysAbiExport(
        Nid = "388LcMWHRCA",
        ExportName = "fabs",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFabs(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        return ReturnDouble(ctx, Math.Abs(x));
    }

    [SysAbiExport(
        Nid = "HUbZmOnT-Dg",
        ExportName = "atan2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAtan2(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, Math.Atan2(x, y));
    }

    [SysAbiExport(
        Nid = "9LCjpWyQ5Zc",
        ExportName = "pow",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatPow(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, Math.Pow(x, y));
    }

    [SysAbiExport(
        Nid = "YFoOw5GkkK0",
        ExportName = "hypot",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatHypot(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, Hypot(x, y));
    }

    [SysAbiExport(
        Nid = "pKwslsMUmSk",
        ExportName = "fmod",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFmod(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, x % y);
    }

    [SysAbiExport(
        Nid = "pv2etu4pocs",
        ExportName = "remainder",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRemainder(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, Math.IEEERemainder(x, y));
    }

    [SysAbiExport(
        Nid = "BEFy1ZFv8Fw",
        ExportName = "copysign",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCopysign(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, CopySign(x, y));
    }

    [SysAbiExport(
        Nid = "Zs4p6RemDxM",
        ExportName = "fdim",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFdim(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, double.IsNaN(x) || double.IsNaN(y) ? double.NaN : (x > y ? x - y : 0.0));
    }

    [SysAbiExport(
        Nid = "fiOgmWkP+Xc",
        ExportName = "fmax",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFmax(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, FMax(x, y));
    }

    [SysAbiExport(
        Nid = "iU0z6SdUNbI",
        ExportName = "fmin",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFmin(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        return ReturnDouble(ctx, FMin(x, y));
    }

    [SysAbiExport(
        Nid = "XI0YDgH8x1c",
        ExportName = "remquo",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRemquo(CpuContext ctx)
    {
        var x = GetDouble(ctx, 0);
        var y = GetDouble(ctx, 1);
        var quotientAddress = ctx[CpuRegister.Rdi];
        var quotient = ComputeRemQuo(x, y, out var remainder);
        if (quotientAddress == 0 || !ctx.TryWriteInt32(quotientAddress, quotient))
        {
            ReturnDouble(ctx, remainder);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }
        return ReturnDouble(ctx, remainder);
    }

    [SysAbiExport(
        Nid = "Q4rRL34CEeE",
        ExportName = "sinf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatSinf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Sin(x));
    }

    [SysAbiExport(
        Nid = "-P6FNMzk2Kc",
        ExportName = "cosf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCosf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Cos(x));
    }

    [SysAbiExport(
        Nid = "ZE6RNL+eLbk",
        ExportName = "tanf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTanf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Tan(x));
    }

    [SysAbiExport(
        Nid = "GZWjF-YIFFk",
        ExportName = "asinf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAsinf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Asin(x));
    }

    [SysAbiExport(
        Nid = "QI-x0SL8jhw",
        ExportName = "acosf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAcosf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Acos(x));
    }

    [SysAbiExport(
        Nid = "weDug8QD-lE",
        ExportName = "atanf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAtanf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Atan(x));
    }

    [SysAbiExport(
        Nid = "1t1-JoZ0sZQ",
        ExportName = "sinhf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatSinhf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Sinh(x));
    }

    [SysAbiExport(
        Nid = "RCQAffkEh9A",
        ExportName = "coshf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCoshf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Cosh(x));
    }

    [SysAbiExport(
        Nid = "SAd0Z3wKwLA",
        ExportName = "tanhf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTanhf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Tanh(x));
    }

    [SysAbiExport(
        Nid = "8zsu04XNsZ4",
        ExportName = "expf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatExpf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Exp(x));
    }

    [SysAbiExport(
        Nid = "wuAQt-j+p4o",
        ExportName = "exp2f",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatExp2f(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Pow(2.0, x));
    }

    [SysAbiExport(
        Nid = "RQXLbdT2lc4",
        ExportName = "logf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLogf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Log(x));
    }

    [SysAbiExport(
        Nid = "hsi9drzHR2k",
        ExportName = "log2f",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLog2f(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Log2(x));
    }

    [SysAbiExport(
        Nid = "lhpd6Wk6ccs",
        ExportName = "log10f",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatLog10f(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Log10(x));
    }

    [SysAbiExport(
        Nid = "Q+xU11-h0xQ",
        ExportName = "sqrtf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatSqrtf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, MathF.Sqrt(x));
    }

    [SysAbiExport(
        Nid = "GlelR9EEeck",
        ExportName = "cbrtf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCbrtf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, (float)Math.Cbrt(x));
    }

    [SysAbiExport(
        Nid = "GAUuLKGhsCw",
        ExportName = "ceilf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCeilf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, MathF.Ceiling(x));
    }

    [SysAbiExport(
        Nid = "mKhVDmYciWA",
        ExportName = "floorf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFloorf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, MathF.Floor(x));
    }

    [SysAbiExport(
        Nid = "Vo8rvWtZw3g",
        ExportName = "truncf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTruncf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, MathF.Truncate(x));
    }

    [SysAbiExport(
        Nid = "DDHG1a6+3q0",
        ExportName = "roundf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRoundf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, MathF.Round(x, MidpointRounding.AwayFromZero));
    }

    [SysAbiExport(
        Nid = "q5WzucyVSkM",
        ExportName = "rintf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRintf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, RoundForMxcsr(ctx, x));
    }

    [SysAbiExport(
        Nid = "c+4r-T-tEIc",
        ExportName = "nearbyintf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatNearbyintf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, RoundForMxcsr(ctx, x));
    }

    [SysAbiExport(
        Nid = "fmT2cjPoWBs",
        ExportName = "fabsf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFabsf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        return ReturnFloat(ctx, MathF.Abs(x));
    }

    [SysAbiExport(
        Nid = "EH-x713A99c",
        ExportName = "atan2f",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatAtan2f(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, (float)Math.Atan2(x, y));
    }

    [SysAbiExport(
        Nid = "1D0H2KNjshE",
        ExportName = "powf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatPowf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, (float)Math.Pow(x, y));
    }

    [SysAbiExport(
        Nid = "iz2shAGFIxc",
        ExportName = "hypotf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatHypotf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, (float)Hypot(x, y));
    }

    [SysAbiExport(
        Nid = "88Vv-AzHVj8",
        ExportName = "fmodf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFmodf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, x % y);
    }

    [SysAbiExport(
        Nid = "eS+MVq+Lltw",
        ExportName = "remainderf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRemainderf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, (float)Math.IEEERemainder(x, y));
    }

    [SysAbiExport(
        Nid = "x-04iOzl1xs",
        ExportName = "copysignf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatCopysignf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, CopySign(x, y));
    }

    [SysAbiExport(
        Nid = "yb9iUBPkSS0",
        ExportName = "fdimf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFdimf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, float.IsNaN(x) || float.IsNaN(y) ? float.NaN : (x > y ? x - y : 0.0f));
    }

    [SysAbiExport(
        Nid = "Lyx2DzUL7Lc",
        ExportName = "fmaxf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFmaxf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, FMax(x, y));
    }

    [SysAbiExport(
        Nid = "uVRcM2yFdP4",
        ExportName = "fminf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatFminf(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        return ReturnFloat(ctx, FMin(x, y));
    }

    [SysAbiExport(
        Nid = "AqpZU2Njrmk",
        ExportName = "remquof",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatRemquof(CpuContext ctx)
    {
        var x = GetFloat(ctx, 0);
        var y = GetFloat(ctx, 1);
        var quotientAddress = ctx[CpuRegister.Rdi];
        var quotient = ComputeRemQuo(x, y, out var remainder);
        if (quotientAddress == 0 || !ctx.TryWriteInt32(quotientAddress, quotient))
        {
            ReturnFloat(ctx, (float)remainder);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }
        return ReturnFloat(ctx, (float)remainder);
    }

    [SysAbiExport(
        Nid = "+xU0WKT8mDc",
        ExportName = "isalpha",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsalpha(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiAlpha(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "GcFKlTJEMkI",
        ExportName = "isupper",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsupper(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiUpper(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "KqYTqtSfGos",
        ExportName = "islower",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIslower(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiLower(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "JWBr5N8zyNE",
        ExportName = "isdigit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsdigit(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiDigit(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "srzSVSbKn7M",
        ExportName = "isxdigit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsxdigit(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiXDigit(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "wazw2x2m3DQ",
        ExportName = "isspace",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsspace(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiSpace(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "I6Z-684E2C4",
        ExportName = "ispunct",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIspunct(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiPunct(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "4uJJNi+C9wk",
        ExportName = "isalnum",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsalnum(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiAlnum(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "eGkOpTojJl4",
        ExportName = "isprint",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsprint(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiPrint(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "rrgxakQtvc0",
        ExportName = "isgraph",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIsgraph(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiGraph(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "akpGErA1zdg",
        ExportName = "iscntrl",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIscntrl(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiControl(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "PqF+kHW-2WQ",
        ExportName = "tolower",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTolower(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        if (c == -1)
        {
            return ReturnInt(ctx, -1);
        }
        return ReturnInt(ctx, IsAsciiUpper(c) ? c + ('a' - 'A') : c);
    }

    [SysAbiExport(
        Nid = "TYE4irxSmko",
        ExportName = "toupper",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatToupper(CpuContext ctx)
    {
        var c = unchecked((int)ctx[CpuRegister.Rdi]);
        if (c == -1)
        {
            return ReturnInt(ctx, -1);
        }
        return ReturnInt(ctx, IsAsciiLower(c) ? c - ('a' - 'A') : c);
    }

    [SysAbiExport(
        Nid = "D-qDARDb1aM",
        ExportName = "iswalpha",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswalpha(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiAlpha(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "1QcrrL9UDRQ",
        ExportName = "iswupper",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswupper(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiUpper(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "Ok8KPy3nFls",
        ExportName = "iswlower",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswlower(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiLower(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "n0kT+8Eeizs",
        ExportName = "iswdigit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswdigit(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiDigit(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "cjmSjRlnMAs",
        ExportName = "iswxdigit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswxdigit(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiXDigit(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "vqtytrxgLMs",
        ExportName = "iswspace",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswspace(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiSpace(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "AEPvEZkaLsU",
        ExportName = "iswpunct",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswpunct(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiPunct(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "wDmL2EH0CBs",
        ExportName = "iswalnum",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswalnum(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiAlnum(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "U7IhU4VEB-0",
        ExportName = "iswprint",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswprint(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiPrint(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "wjG0GyCyaP0",
        ExportName = "iswgraph",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswgraph(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiGraph(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "6A+1YZ79qFk",
        ExportName = "iswcntrl",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatIswcntrl(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiControl(c) ? 1 : 0);
    }

    [SysAbiExport(
        Nid = "J3J1T9fjUik",
        ExportName = "towlower",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTowlower(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiUpper(c) ? c + ('a' - 'A') : c);
    }

    [SysAbiExport(
        Nid = "1uf1SQsj5go",
        ExportName = "towupper",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompatTowupper(CpuContext ctx)
    {
        var c = unchecked((int)(uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, IsAsciiLower(c) ? c - ('a' - 'A') : c);
    }

    [SysAbiExport(
        Nid = "IBn9qjWnXIw",
        ExportName = "__popcountsi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerPopcountsi2(CpuContext ctx)
    {
        var value = unchecked((uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, BitOperations.PopCount(value));
    }

    [SysAbiExport(
        Nid = "m4S+lkRvTVY",
        ExportName = "__popcountdi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerPopcountdi2(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return ReturnInt(ctx, BitOperations.PopCount(value));
    }

    [SysAbiExport(
        Nid = "9xUnIQ53Ao4",
        ExportName = "__paritysi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerParitysi2(CpuContext ctx)
    {
        var value = unchecked((uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, BitOperations.PopCount(value) & 1);
    }

    [SysAbiExport(
        Nid = "RDeUB6JGi1U",
        ExportName = "__paritydi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerParitydi2(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return ReturnInt(ctx, BitOperations.PopCount(value) & 1);
    }

    [SysAbiExport(
        Nid = "ptL8XWgpGS4",
        ExportName = "__clzsi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerClzsi2(CpuContext ctx)
    {
        var value = unchecked((uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, value == 0 ? 32 : BitOperations.LeadingZeroCount(value));
    }

    [SysAbiExport(
        Nid = "gCf7+aGEhnU",
        ExportName = "__clzdi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerClzdi2(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return ReturnInt(ctx, value == 0 ? 64 : BitOperations.LeadingZeroCount(value));
    }

    [SysAbiExport(
        Nid = "2NvhgiBTcVE",
        ExportName = "__ctzsi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerCtzsi2(CpuContext ctx)
    {
        var value = unchecked((uint)ctx[CpuRegister.Rdi]);
        return ReturnInt(ctx, value == 0 ? 32 : BitOperations.TrailingZeroCount(value));
    }

    [SysAbiExport(
        Nid = "yDPuV0SXp7g",
        ExportName = "__ctzdi2",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerCtzdi2(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return ReturnInt(ctx, value == 0 ? 64 : BitOperations.TrailingZeroCount(value));
    }

    [SysAbiExport(
        Nid = "CS91br93fag",
        ExportName = "__ashldi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerAshldi3(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        var shift = unchecked((int)ctx[CpuRegister.Rsi]) & 63;
        return ReturnUInt64(ctx, value << shift);
    }

    [SysAbiExport(
        Nid = "fSZ+gbf8Ekc",
        ExportName = "__ashrdi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerAshrdi3(CpuContext ctx)
    {
        var value = unchecked((long)ctx[CpuRegister.Rdi]);
        var shift = unchecked((int)ctx[CpuRegister.Rsi]) & 63;
        return ReturnUInt64(ctx, unchecked((ulong)(value >> shift)));
    }

    [SysAbiExport(
        Nid = "18E1gOH7cmk",
        ExportName = "__lshrdi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerLshrdi3(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        var shift = unchecked((int)ctx[CpuRegister.Rsi]) & 63;
        return ReturnUInt64(ctx, value >> shift);
    }

    [SysAbiExport(
        Nid = "Hf8hPlDoVsw",
        ExportName = "__muldi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerMuldi3(CpuContext ctx)
    {
        var left = ctx[CpuRegister.Rdi];
        var right = ctx[CpuRegister.Rsi];
        return ReturnUInt64(ctx, unchecked(left * right));
    }

    [SysAbiExport(
        Nid = "9daYeu+0Y-A",
        ExportName = "__divdi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerDivdi3(CpuContext ctx)
    {
        var left = unchecked((long)ctx[CpuRegister.Rdi]);
        var right = unchecked((long)ctx[CpuRegister.Rsi]);
        if (right == 0)
        {
            return ReturnUInt64(ctx, 0);
        }
        var result = left == long.MinValue && right == -1 ? long.MinValue : left / right;
        return ReturnUInt64(ctx, unchecked((ulong)result));
    }

    [SysAbiExport(
        Nid = "tX8ED4uIAsQ",
        ExportName = "__udivdi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerUdivdi3(CpuContext ctx)
    {
        var left = ctx[CpuRegister.Rdi];
        var right = ctx[CpuRegister.Rsi];
        return ReturnUInt64(ctx, right == 0 ? 0 : left / right);
    }

    [SysAbiExport(
        Nid = "gQFVRFgFi48",
        ExportName = "__moddi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerModdi3(CpuContext ctx)
    {
        var left = unchecked((long)ctx[CpuRegister.Rdi]);
        var right = unchecked((long)ctx[CpuRegister.Rsi]);
        if (right == 0)
        {
            return ReturnUInt64(ctx, 0);
        }
        var result = left == long.MinValue && right == -1 ? 0 : left % right;
        return ReturnUInt64(ctx, unchecked((ulong)result));
    }

    [SysAbiExport(
        Nid = "+wj27DzRPpo",
        ExportName = "__umoddi3",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerUmoddi3(CpuContext ctx)
    {
        var left = ctx[CpuRegister.Rdi];
        var right = ctx[CpuRegister.Rsi];
        return ReturnUInt64(ctx, right == 0 ? 0 : left % right);
    }

    [SysAbiExport(
        Nid = "BMVIEbwpP+8",
        ExportName = "__floatdidf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerFloatdidf(CpuContext ctx)
    {
        var value = unchecked((long)ctx[CpuRegister.Rdi]);
        return ReturnDouble(ctx, value);
    }

    [SysAbiExport(
        Nid = "2SSK3UFPqgQ",
        ExportName = "__floatdisf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerFloatdisf(CpuContext ctx)
    {
        var value = unchecked((long)ctx[CpuRegister.Rdi]);
        return ReturnFloat(ctx, value);
    }

    [SysAbiExport(
        Nid = "1RNxpXpVWs4",
        ExportName = "__floatundidf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerFloatundidf(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return ReturnDouble(ctx, value);
    }

    [SysAbiExport(
        Nid = "9tnIVFbvOrw",
        ExportName = "__floatundisf",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CompilerFloatundisf(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return ReturnFloat(ctx, value);
    }

}
