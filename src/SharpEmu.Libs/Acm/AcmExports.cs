// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;
using System.Collections.Concurrent;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Acm;

public static class AcmExports
{
    private const int AcmBatchErrorBytes = 32;
    private static readonly ConcurrentDictionary<uint, byte> Contexts = new();
    private static int _nextContextHandle;
    private static int _nextBatchHandle;

    // SHARPEMU_RUNTIMEDEBUG_ACM_COMMAND_TRACE_V1_3_3
    // Diagnostic-only, dormant unless the RuntimeDebug session enables it.
    private static readonly bool _runtimeDebugTraceAcmCommandsV133 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_TRACE_ACM_COMMANDS"),
            "1",
            StringComparison.Ordinal);
    private static long _runtimeDebugAcmCommandTraceCountV133;

    [SysAbiExport(
        Nid = "ZIXln2K3XMk",
        ExportName = "sceAcmContextCreate",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmContextCreate(CpuContext ctx)
    {
        var outContextAddress = ctx[CpuRegister.Rdi];
        if (outContextAddress == 0)
        {
            return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        var handle = unchecked((uint)Interlocked.Increment(ref _nextContextHandle));
        Span<byte> handleBytes = stackalloc byte[sizeof(uint)];
        BinaryPrimitives.WriteUInt32LittleEndian(handleBytes, handle);
        if (!ctx.Memory.TryWrite(outContextAddress, handleBytes))
        {
            return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        Contexts[handle] = 0;
        Trace($"context_create context={handle}");
        return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);
    }

    [SysAbiExport(
        Nid = "jBgBjAj02R8",
        ExportName = "sceAcmContextDestroy",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmContextDestroy(CpuContext ctx)
    {
        var context = unchecked((uint)ctx[CpuRegister.Rdi]);
        Contexts.TryRemove(context, out _);
        Trace($"context_destroy context={context}");
        return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);
    }

    [SysAbiExport(
        Nid = "tW9W+CAG4FE",
        ExportName = "sceAcmBatchStartBuffer",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchStartBuffer(CpuContext ctx)
    {
        var context = unchecked((uint)ctx[CpuRegister.Rdi]);
        var commandsAddress = ctx[CpuRegister.Rsi];
        var commandsSize = ctx[CpuRegister.Rdx];
        var errorAddress = ctx[CpuRegister.Rcx];
        var batchAddress = ctx[CpuRegister.R8];

        if (!Contexts.ContainsKey(context) ||
            batchAddress == 0 ||
            (commandsSize != 0 && commandsAddress == 0))
        {
            return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        TraceRuntimeDebugAcmPayloadV133(
            ctx,
            "buffer",
            context,
            commandsAddress,
            commandsSize,
            1);
        return CompleteBatchStart(ctx, context, 1, errorAddress, batchAddress);
    }

    [SysAbiExport(
        Nid = "8fe55ktlNVo",
        ExportName = "sceAcmBatchStartBuffers",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchStartBuffers(CpuContext ctx)
    {
        var context = unchecked((uint)ctx[CpuRegister.Rdi]);
        var infoCount = unchecked((uint)ctx[CpuRegister.Rsi]);
        var infoArrayAddress = ctx[CpuRegister.Rdx];
        var errorAddress = ctx[CpuRegister.Rcx];
        var batchAddress = ctx[CpuRegister.R8];

        if (!Contexts.ContainsKey(context) ||
            batchAddress == 0 ||
            (infoCount != 0 && infoArrayAddress == 0))
        {
            return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        var infoProbeBytes = Math.Min((ulong)infoCount * 32UL, 256UL);
        TraceRuntimeDebugAcmPayloadV133(
            ctx,
            "buffers-info",
            context,
            infoArrayAddress,
            infoProbeBytes,
            infoCount);
        return CompleteBatchStart(ctx, context, infoCount, errorAddress, batchAddress);
    }

    // DSP batch submission and synchronization. The emulator runs no ACM DSP
    // jobs (FFT/panner/reverb output stays silent), but Scream's workers trap
    // with int 0x41/0x42 asserts whenever a submission call reports failure,
    // so the whole batch surface must report success.
    [SysAbiExport(
        Nid = "WeZOIm8+8WI",
        ExportName = "sceAcmBatchInitialize",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchInitialize(CpuContext ctx) =>
        ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);

    [SysAbiExport(
        Nid = "Mk1xvQXIdkk",
        ExportName = "sceAcmBatchInitializeLite",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchInitializeLite(CpuContext ctx) =>
        ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);

    [SysAbiExport(
        Nid = "A5NXCXK5Gfc",
        ExportName = "sceAcmBatchStart",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchStart(CpuContext ctx) =>
        ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);

    [SysAbiExport(
        Nid = "S3BPrjCfZ90",
        ExportName = "sceAcmBatchStartMultiple",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchStartMultiple(CpuContext ctx) =>
        ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);

    [SysAbiExport(
        Nid = "uqDIauipRbo",
        ExportName = "sceAcmBatchProcess",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchProcess(CpuContext ctx) =>
        ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);

    [SysAbiExport(
        Nid = "RLN3gRlXJLE",
        ExportName = "sceAcmBatchWait",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchWait(CpuContext ctx)
    {
        var context = unchecked((uint)ctx[CpuRegister.Rdi]);
        return ctx.SetReturn(
            Contexts.ContainsKey(context)
                ? OrbisGen2Result.ORBIS_GEN2_OK
                : OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
    }

    [SysAbiExport(
        Nid = "r7z5YQFZo+U",
        ExportName = "sceAcmBatchJobNotification",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmBatchJobNotification(CpuContext ctx) =>
        AdvanceBatchInfo(ctx, 32);

    [SysAbiExport(
        Nid = "u70oWo92SYQ",
        ExportName = "sceAcm_ConvReverb_SharedInput",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmConvReverbSharedInput(CpuContext ctx) =>
        AdvanceBatchInfo(ctx, 1024);

    [SysAbiExport(
        Nid = "9nLbWmRDpa8",
        ExportName = "sceAcm_ConvReverb_SharedIr",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmConvReverbSharedIr(CpuContext ctx) =>
        AdvanceBatchInfo(ctx, 1024);

    [SysAbiExport(
        Nid = "KovqaFbmtsM",
        ExportName = "sceAcm_FFT",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmFft(CpuContext ctx) =>
        AdvanceBatchInfo(ctx, 256);

    [SysAbiExport(
        Nid = "DR-ZCmvVR9Q",
        ExportName = "sceAcm_IFFT",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmIfft(CpuContext ctx) =>
        AdvanceBatchInfo(ctx, 256);

    [SysAbiExport(
        Nid = "LA4RCNKnFjg",
        ExportName = "sceAcm_Panner",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceAcm")]
    public static int AcmPanner(CpuContext ctx) =>
        AdvanceBatchInfo(ctx, 512);

    internal static void ResetForTests()
    {
        Contexts.Clear();
        Interlocked.Exchange(ref _nextContextHandle, 0);
        Interlocked.Exchange(ref _nextBatchHandle, 0);
    }

    private static void TraceRuntimeDebugAcmPayloadV133(
        CpuContext ctx,
        string kind,
        uint context,
        ulong address,
        ulong size,
        uint count)
    {
        if (!_runtimeDebugTraceAcmCommandsV133)
        {
            return;
        }

        var trace = Interlocked.Increment(
            ref _runtimeDebugAcmCommandTraceCountV133);
        if (trace > 32 && (trace & (trace - 1)) != 0)
        {
            return;
        }

        var take = (int)Math.Min(size, 256UL);
        if (address == 0 || take <= 0)
        {
            Console.Error.WriteLine(
                $"[V1.3.3][ACM_COMMAND] n={trace} kind={kind} " +
                $"context={context} address=0x{address:X16} size=0x{size:X} " +
                $"count={count} readable=0");
            return;
        }

        var bytes = new byte[take];
        var readable = ctx.Memory.TryRead(address, bytes);
        Console.Error.WriteLine(
            $"[V1.3.3][ACM_COMMAND] n={trace} kind={kind} " +
            $"context={context} address=0x{address:X16} size=0x{size:X} " +
            $"count={count} readable={(readable ? 1 : 0)} " +
            $"head={(readable ? Convert.ToHexString(bytes) : string.Empty)}");
    
        // SHARPEMU_RUNTIMEDEBUG_ACM_DEREF_TRACE_V1_3_4
        // V1.3.3 proved the 32-byte payload is a BufferInfo structure.
        // Probe all qwords conservatively instead of assuming the ABI layout.
        if (readable &&
            kind == "buffers-info" &&
            bytes.Length >= 32)
        {
            var q0 = BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(0, 8));
            var q1 = BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(8, 8));
            var q2 = BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(16, 8));
            var q3 = BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(24, 8));

            Console.Error.WriteLine(
                $"[V1.3.4][ACM_DEREF] n={trace} context={context} " +
                $"q0=0x{q0:X16}:{ReadRuntimeDebugAcmPointerHeadV134(ctx, q0)} " +
                $"q1=0x{q1:X16}:{ReadRuntimeDebugAcmPointerHeadV134(ctx, q1)} " +
                $"q2=0x{q2:X16}:{ReadRuntimeDebugAcmPointerHeadV134(ctx, q2)} " +
                $"q3=0x{q3:X16}:{ReadRuntimeDebugAcmPointerHeadV134(ctx, q3)}");
        }
}
    private static string ReadRuntimeDebugAcmPointerHeadV134(
        CpuContext ctx,
        ulong address)
    {
        if (address < 0x10000)
        {
            return "skip";
        }

        var probe = new byte[96];
        if (!ctx.Memory.TryRead(address, probe))
        {
            return "unreadable";
        }

        return Convert.ToHexString(probe);
    }
    private static int CompleteBatchStart(
        CpuContext ctx,
        uint context,
        uint infoCount,
        ulong errorAddress,
        ulong batchAddress)
    {
        if (errorAddress != 0)
        {
            Span<byte> error = stackalloc byte[AcmBatchErrorBytes];
            error.Clear();
            if (!ctx.Memory.TryWrite(errorAddress, error))
            {
                return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            }
        }

        var batch = unchecked((uint)Interlocked.Increment(ref _nextBatchHandle));
        Span<byte> batchBytes = stackalloc byte[sizeof(uint)];
        BinaryPrimitives.WriteUInt32LittleEndian(batchBytes, batch);
        if (!ctx.Memory.TryWrite(batchAddress, batchBytes))
        {
            return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        Trace($"batch_start context={context} count={infoCount} batch={batch}");
        return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);
    }

    private static int AdvanceBatchInfo(CpuContext ctx, ulong byteCount)
    {
        var infoAddress = ctx[CpuRegister.Rdi];
        if (infoAddress == 0)
        {
            return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);
        }

        Span<byte> info = stackalloc byte[24];
        if (!ctx.Memory.TryRead(infoAddress, info))
        {
            return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        var buffer = BinaryPrimitives.ReadUInt64LittleEndian(info);
        var offset = BinaryPrimitives.ReadUInt64LittleEndian(info[8..]);
        var size = BinaryPrimitives.ReadUInt64LittleEndian(info[16..]);
        if (buffer != 0 && size != 0)
        {
            var nextOffset = offset > ulong.MaxValue - byteCount
                ? ulong.MaxValue
                : offset + byteCount;
            BinaryPrimitives.WriteUInt64LittleEndian(info[8..], Math.Min(size, nextOffset));
            if (!ctx.Memory.TryWrite(infoAddress, info))
            {
                return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            }
        }

        return ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_OK);
    }

    private static void Trace(string message)
    {
        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_LOG_ACM"),
                "1",
                StringComparison.Ordinal))
        {
            Console.Error.WriteLine($"[LOADER][TRACE] acm.{message}");
        }
    }
}


