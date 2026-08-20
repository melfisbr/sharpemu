// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using SharpEmu.Libs.Ampr;
using System.Collections.Concurrent;
using System.Threading;

namespace SharpEmu.Libs.Kernel;

public static class KernelAprCompatExports
{
    private static readonly ConcurrentDictionary<uint, AprSubmission> _submittedCommandBuffers = new();
    private static readonly BlockingCollection<AprSubmission> _aprAsyncQueue =
        new(new ConcurrentQueue<AprSubmission>(), boundedCapacity: 256);
    private static int _nextSubmissionId;
    private static int _aprWaitTraceCount;
    private static int _aprWorkerStarted;
    private static Thread? _aprWorker;
    private static long _aprQueuedCountV1825;
    private static long _aprCompletedCountV1825;
    private static long _aprWaitBlockingCountV1825;
    private static long _aprWaitImmediateCountV1825;
    private static long _aprSyncFallbackCountV1825;
    private static int _aprMaxQueueDepthV1825;
    private static readonly bool _traceApr =
        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_AMPR"), "1", StringComparison.Ordinal);

    // SHARPEMU_APR_ASYNC_SUBMISSION_PIPELINE_V1_8_25
    private sealed class AprSubmission : IDisposable
    {
        public AprSubmission(
            uint submissionId,
            ulong commandBuffer,
            ulong priority,
            ulong resultAddress,
            ICpuMemory memory,
            Generation generation,
            AmprExports.AprCommandBufferSubmissionSnapshot? snapshot,
            bool autoRemove)
        {
            SubmissionId = submissionId;
            CommandBuffer = commandBuffer;
            Priority = priority;
            ResultAddress = resultAddress;
            Memory = memory;
            Generation = generation;
            Snapshot = snapshot;
            AutoRemove = autoRemove;
            QueuedTimestamp = System.Diagnostics.Stopwatch.GetTimestamp();
        }

        public uint SubmissionId { get; }
        public ulong CommandBuffer { get; }
        public ulong Priority { get; }
        public ulong ResultAddress { get; }
        public ICpuMemory Memory { get; }
        public Generation Generation { get; }
        public AmprExports.AprCommandBufferSubmissionSnapshot? Snapshot { get; }
        public bool AutoRemove { get; }
        public long QueuedTimestamp { get; }
        public ManualResetEventSlim Completion { get; } = new(false, 0);
        public int CompletionResult;
        public int Completed;

        public void Dispose() => Completion.Dispose();
    }

    private static bool IsAprAsyncPipelineEnabled() =>
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_APR_ASYNC_PIPELINE"),
            "0",
            StringComparison.Ordinal);

    private static uint NextSubmissionId()
    {
        var submissionId = unchecked((uint)Interlocked.Increment(ref _nextSubmissionId));
        if (submissionId == 0)
        {
            submissionId = unchecked((uint)Interlocked.Increment(ref _nextSubmissionId));
        }

        return submissionId;
    }

    private static int TryCreateAsyncSubmission(
        CpuContext ctx,
        ulong commandBuffer,
        ulong priority,
        ulong resultAddress,
        bool autoRemove,
        out AprSubmission? submission)
    {
        submission = null;
        var captureResult = AmprExports.TryCaptureCommandBufferSubmission(
            ctx,
            commandBuffer,
            out var snapshot);
        if (captureResult != (int)OrbisGen2Result.ORBIS_GEN2_OK ||
            snapshot is null)
        {
            return captureResult;
        }

        submission = new AprSubmission(
            NextSubmissionId(),
            commandBuffer,
            priority,
            resultAddress,
            ctx.Memory,
            ctx.TargetGeneration,
            snapshot,
            autoRemove);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static AprSubmission CreateSynchronousSubmission(
        CpuContext ctx,
        ulong commandBuffer,
        ulong priority,
        ulong resultAddress,
        bool autoRemove) =>
        new(
            NextSubmissionId(),
            commandBuffer,
            priority,
            resultAddress,
            ctx.Memory,
            ctx.TargetGeneration,
            snapshot: null,
            autoRemove);

    private static void EnqueueAprSubmission(AprSubmission submission)
    {
        _submittedCommandBuffers[submission.SubmissionId] = submission;
        EnsureAprAsyncWorker();
        _aprAsyncQueue.Add(submission);

        var queued = Interlocked.Increment(ref _aprQueuedCountV1825);
        var depth = _aprAsyncQueue.Count;
        var observed = Volatile.Read(ref _aprMaxQueueDepthV1825);
        while (depth > observed)
        {
            var prior = Interlocked.CompareExchange(
                ref _aprMaxQueueDepthV1825,
                depth,
                observed);
            if (prior == observed)
            {
                break;
            }

            observed = prior;
        }

        if (ShouldTraceAprAsyncCount(queued))
        {
            Console.Error.WriteLine(
                $"[APR-ASYNC-1825] queue n={queued} id=0x{submission.SubmissionId:X8} " +
                $"cmd=0x{submission.CommandBuffer:X16} records={submission.Snapshot?.WriteOffset ?? 0} " +
                $"depth={depth} auto_remove={submission.AutoRemove}");
        }
    }

    private static void EnsureAprAsyncWorker()
    {
        if (Volatile.Read(ref _aprWorkerStarted) != 0)
        {
            return;
        }

        if (Interlocked.CompareExchange(ref _aprWorkerStarted, 1, 0) != 0)
        {
            return;
        }

        _aprWorker = new Thread(AprWorkerMain)
        {
            IsBackground = true,
            Name = "SharpEmu-APR",
            Priority = ThreadPriority.Normal,
        };
        _aprWorker.Start();
        Console.Error.WriteLine(
            "[APR-ASYNC-1825] worker_started name='SharpEmu-APR'");
    }

    private static void AprWorkerMain()
    {
        foreach (var submission in _aprAsyncQueue.GetConsumingEnumerable())
        {
            var started = System.Diagnostics.Stopwatch.GetTimestamp();
            var before = AmprExports.GetAprIoPerfSnapshotV1825();
            var result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;

            try
            {
                var workerContext = new CpuContext(
                    submission.Memory,
                    submission.Generation);
                result = submission.Snapshot is { } snapshot
                    ? AmprExports.CompleteCommandBuffer(workerContext, snapshot)
                    : AmprExports.CompleteCommandBuffer(
                        workerContext,
                        submission.CommandBuffer);

                if (result == (int)OrbisGen2Result.ORBIS_GEN2_OK &&
                    submission.ResultAddress != 0 &&
                    !TryWriteAprResult(workerContext, submission.ResultAddress))
                {
                    result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(
                    $"[APR-ASYNC-1825][ERROR] id=0x{submission.SubmissionId:X8} " +
                    $"cmd=0x{submission.CommandBuffer:X16} {ex.GetType().Name}: {ex.Message}");
                result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
            }

            submission.CompletionResult = result;
            Volatile.Write(ref submission.Completed, 1);
            submission.Completion.Set();

            var completed = Interlocked.Increment(ref _aprCompletedCountV1825);
            var after = AmprExports.GetAprIoPerfSnapshotV1825();
            if (ShouldTraceAprAsyncCount(completed))
            {
                var frequency = (double)System.Diagnostics.Stopwatch.Frequency;
                var elapsedMs =
                    (System.Diagnostics.Stopwatch.GetTimestamp() - started) *
                    1000.0 / frequency;
                var queueDelayMs =
                    (started - submission.QueuedTimestamp) * 1000.0 / frequency;
                var hostReadMs =
                    (after.HostReadTicks - before.HostReadTicks) * 1000.0 / frequency;
                var guestWriteMs =
                    (after.GuestWriteTicks - before.GuestWriteTicks) * 1000.0 / frequency;
                var ioBytes = after.Bytes - before.Bytes;
                var ioReads = after.CompletedReadCount - before.CompletedReadCount;
                Console.Error.WriteLine(
                    $"[APR-ASYNC-1825] complete n={completed} id=0x{submission.SubmissionId:X8} " +
                    $"result=0x{result:X8} queue_ms={queueDelayMs:F3} work_ms={elapsedMs:F3} " +
                    $"reads={ioReads} bytes={ioBytes} host_read_ms={hostReadMs:F3} " +
                    $"guest_write_ms={guestWriteMs:F3} depth={_aprAsyncQueue.Count}");
            }

            if (submission.AutoRemove &&
                _submittedCommandBuffers.TryRemove(
                    submission.SubmissionId,
                    out var removed))
            {
                removed.Dispose();
            }
        }
    }

    private static bool ShouldTraceAprAsyncCount(long count) =>
        count <= 32 || (count > 0 && (count & (count - 1)) == 0);

    private static int CompleteSynchronousSubmission(
        CpuContext ctx,
        AprSubmission submission)
    {
        Interlocked.Increment(ref _aprSyncFallbackCountV1825);
        _submittedCommandBuffers[submission.SubmissionId] = submission;

        var result = AmprExports.CompleteCommandBuffer(
            ctx,
            submission.CommandBuffer);
        if (result == (int)OrbisGen2Result.ORBIS_GEN2_OK &&
            submission.ResultAddress != 0 &&
            !TryWriteAprResult(ctx, submission.ResultAddress))
        {
            result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        submission.CompletionResult = result;
        Volatile.Write(ref submission.Completed, 1);
        submission.Completion.Set();

        if (submission.AutoRemove &&
            _submittedCommandBuffers.TryRemove(
                submission.SubmissionId,
                out var removed))
        {
            removed.Dispose();
        }

        return result;
    }

    [SysAbiExport(
        Nid = "ASoW5WE-UPo",
        ExportName = "sceKernelAprSubmitCommandBufferAndGetResult",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelAprSubmitCommandBufferAndGetResult(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var priority = ctx[CpuRegister.Rsi];
        var resultAddress = ctx[CpuRegister.Rdx];
        var outSubmissionId = ctx[CpuRegister.Rcx];

        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (IsAprAsyncPipelineEnabled())
        {
            var createResult = TryCreateAsyncSubmission(
                ctx,
                commandBuffer,
                priority,
                resultAddress,
                autoRemove: false,
                out var submission);
            if (createResult != (int)OrbisGen2Result.ORBIS_GEN2_OK ||
                submission is null)
            {
                return createResult;
            }

            if (outSubmissionId != 0 &&
                !ctx.TryWriteUInt32(
                    outSubmissionId,
                    submission.SubmissionId))
            {
                submission.Dispose();
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }

            EnqueueAprSubmission(submission);
            TraceApr(
                ctx,
                "submit_get_result_async",
                submission.SubmissionId,
                commandBuffer,
                priority,
                resultAddress);
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        var synchronous = CreateSynchronousSubmission(
            ctx,
            commandBuffer,
            priority,
            resultAddress,
            autoRemove: false);
        var completionResult = CompleteSynchronousSubmission(ctx, synchronous);
        if (completionResult != (int)OrbisGen2Result.ORBIS_GEN2_OK)
        {
            _submittedCommandBuffers.TryRemove(synchronous.SubmissionId, out _);
            synchronous.Dispose();
            return completionResult;
        }

        if (outSubmissionId != 0 &&
            !ctx.TryWriteUInt32(
                outSubmissionId,
                synchronous.SubmissionId))
        {
            _submittedCommandBuffers.TryRemove(synchronous.SubmissionId, out _);
            synchronous.Dispose();
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceApr(
            ctx,
            "submit_get_result_sync",
            synchronous.SubmissionId,
            commandBuffer,
            priority,
            resultAddress);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "rqwFKI4PAiM",
        ExportName = "sceKernelAprWaitCommandBuffer",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelAprWaitCommandBuffer(CpuContext ctx)
    {
        var submissionId = unchecked((uint)ctx[CpuRegister.Rdi]);
        var waitArg1 = ctx[CpuRegister.Rsi];
        var waitArg2 = ctx[CpuRegister.Rdx];

        if (!_submittedCommandBuffers.TryGetValue(
                submissionId,
                out var submission))
        {
            TraceAprWaitFailure(
                ctx,
                "wait_missing",
                submissionId,
                commandBuffer: 0,
                waitArg1,
                waitArg2);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
        }

        if (Volatile.Read(ref submission.Completed) == 0)
        {
            var blocking = Interlocked.Increment(
                ref _aprWaitBlockingCountV1825);
            if (ShouldTraceAprAsyncCount(blocking))
            {
                Console.Error.WriteLine(
                    $"[APR-ASYNC-1825] wait_block n={blocking} " +
                    $"id=0x{submissionId:X8} cmd=0x{submission.CommandBuffer:X16} " +
                    $"depth={_aprAsyncQueue.Count}");
            }

            // Explicit APR wait is the synchronization boundary. Submission and
            // host I/O run on the dedicated APR worker; only the guest thread
            // that actually waits parks here.
            submission.Completion.Wait();
        }
        else
        {
            var immediate = Interlocked.Increment(
                ref _aprWaitImmediateCountV1825);
            if (ShouldTraceAprAsyncCount(immediate))
            {
                Console.Error.WriteLine(
                    $"[APR-ASYNC-1825] wait_ready n={immediate} " +
                    $"id=0x{submissionId:X8} cmd=0x{submission.CommandBuffer:X16}");
            }
        }

        var result = submission.CompletionResult;
        if (_submittedCommandBuffers.TryRemove(
                submissionId,
                out var removed))
        {
            removed.Dispose();
        }

        TraceApr(
            ctx,
            "wait",
            submissionId,
            submission.CommandBuffer,
            waitArg1,
            waitArg2);
        return result;
    }

    [SysAbiExport(
        Nid = "eE4Szl8sil8",
        ExportName = "sceKernelAprSubmitCommandBuffer",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelAprSubmitCommandBuffer(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var priority = ctx[CpuRegister.Rsi];
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (IsAprAsyncPipelineEnabled())
        {
            var createResult = TryCreateAsyncSubmission(
                ctx,
                commandBuffer,
                priority,
                resultAddress: 0,
                autoRemove: true,
                out var submission);
            if (createResult != (int)OrbisGen2Result.ORBIS_GEN2_OK ||
                submission is null)
            {
                return createResult;
            }

            EnqueueAprSubmission(submission);
            TraceApr(
                ctx,
                "submit_async",
                submission.SubmissionId,
                commandBuffer,
                priority,
                0);
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        var synchronous = CreateSynchronousSubmission(
            ctx,
            commandBuffer,
            priority,
            resultAddress: 0,
            autoRemove: true);
        var completionResult = CompleteSynchronousSubmission(ctx, synchronous);
        TraceApr(
            ctx,
            "submit_sync",
            synchronous.SubmissionId,
            commandBuffer,
            priority,
            0);
        return completionResult;
    }

    [SysAbiExport(
        Nid = "qvMUCyyaCSI",
        ExportName = "sceKernelAprSubmitCommandBufferAndGetId",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelAprSubmitCommandBufferAndGetId(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var priority = ctx[CpuRegister.Rsi];
        var outSubmissionId = ctx[CpuRegister.Rdx];
        if (commandBuffer == 0 || outSubmissionId == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (IsAprAsyncPipelineEnabled())
        {
            var createResult = TryCreateAsyncSubmission(
                ctx,
                commandBuffer,
                priority,
                resultAddress: 0,
                autoRemove: false,
                out var submission);
            if (createResult != (int)OrbisGen2Result.ORBIS_GEN2_OK ||
                submission is null)
            {
                return createResult;
            }

            if (!ctx.TryWriteUInt32(
                    outSubmissionId,
                    submission.SubmissionId))
            {
                submission.Dispose();
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }

            EnqueueAprSubmission(submission);
            TraceApr(
                ctx,
                "submit_get_id_async",
                submission.SubmissionId,
                commandBuffer,
                priority,
                outSubmissionId);
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        var synchronous = CreateSynchronousSubmission(
            ctx,
            commandBuffer,
            priority,
            resultAddress: 0,
            autoRemove: false);
        var completionResult = CompleteSynchronousSubmission(ctx, synchronous);
        if (completionResult != (int)OrbisGen2Result.ORBIS_GEN2_OK)
        {
            _submittedCommandBuffers.TryRemove(synchronous.SubmissionId, out _);
            synchronous.Dispose();
            return completionResult;
        }

        if (!ctx.TryWriteUInt32(
                outSubmissionId,
                synchronous.SubmissionId))
        {
            _submittedCommandBuffers.TryRemove(synchronous.SubmissionId, out _);
            synchronous.Dispose();
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceApr(
            ctx,
            "submit_get_id_sync",
            synchronous.SubmissionId,
            commandBuffer,
            priority,
            outSubmissionId);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    // Success stub: the argument layout is unknown and callers tolerate the
    // empty answer (Quake streams fine), so no output payload is written until
    // the real signature is reversed.
    [SysAbiExport(
        Nid = "WvEu7yl3Ivg",
        ExportName = "sceKernelAprGetFileSize",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    // V33: resolve APR file id/path to an actual 64-bit file size.
    // The runtime resolver already publishes stable APR ids through
    // AmprFileRegistry. For compatibility with callers that pass a path
    // directly, a readable guest UTF-8 path is also accepted.
    public static int KernelAprGetFileSize(CpuContext ctx)
    {
        var fileOrPath = ctx[CpuRegister.Rdi];
        var sizeAddress = ctx[CpuRegister.Rsi];
        if (fileOrPath == 0 || sizeAddress == 0)
        {
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        string? hostPath = null;
        if (fileOrPath <= uint.MaxValue &&
            AmprFileRegistry.TryGetHostPath(unchecked((uint)fileOrPath), out var registeredPath))
        {
            hostPath = registeredPath;
        }
        else if (KernelMemoryCompatExports.TryReadNullTerminatedUtf8(
                     ctx,
                     fileOrPath,
                     4096,
                     out var guestPath))
        {
            hostPath = KernelMemoryCompatExports.ResolveGuestPath(guestPath);
        }

        if (string.IsNullOrEmpty(hostPath) || !File.Exists(hostPath))
        {
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        ulong fileSize;
        try
        {
            fileSize = checked((ulong)new FileInfo(hostPath).Length);
        }
        catch
        {
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        if (!ctx.TryWriteUInt64(sizeAddress, fileSize))
        {
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        if (_traceApr)
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] apr_get_file_size key=0x{fileOrPath:X16} " +
                $"size={fileSize} host='{hostPath}'");
        }

        return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_OK);
    }

    private static bool TryWriteAprResult(CpuContext ctx, ulong resultAddress)
    {
        Span<byte> result = stackalloc byte[sizeof(ulong)];
        result.Clear();
        return ctx.Memory.TryWrite(resultAddress, result);
    }

    private static void TraceApr(
        CpuContext ctx,
        string operation,
        uint submissionId,
        ulong commandBuffer,
        ulong priority,
        ulong aux)
    {
        if (!_traceApr)
        {
            return;
        }

        var returnRip = 0UL;
        _ = ctx.TryReadUInt64(ctx[CpuRegister.Rsp], out returnRip);
        Console.Error.WriteLine(
            $"[LOADER][TRACE] apr.{operation}: id=0x{submissionId:X8} cmd=0x{commandBuffer:X16} priority=0x{priority:X16} aux=0x{aux:X16} ret=0x{returnRip:X16}");
        if (aux != 0 &&
            ctx.TryReadUInt64(aux, out var result0) &&
            ctx.TryReadUInt64(aux + sizeof(ulong), out var result1))
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] apr.{operation}.result: addr=0x{aux:X16} q0=0x{result0:X16} q1=0x{result1:X16}");
        }
    }

    private static void TraceAprWaitFailure(
        CpuContext ctx,
        string operation,
        uint submissionId,
        ulong commandBuffer,
        ulong priority,
        ulong resultAddress)
    {
        if (!_traceApr)
        {
            return;
        }

        var traceCount = Interlocked.Increment(ref _aprWaitTraceCount);
        if (traceCount > 32 && (traceCount & 0x3FF) != 0)
        {
            return;
        }

        var returnRip = 0UL;
        _ = ctx.TryReadUInt64(ctx[CpuRegister.Rsp], out returnRip);
        Console.Error.WriteLine(
            $"[LOADER][TRACE] apr.{operation}: id=0x{submissionId:X8} cmd=0x{commandBuffer:X16} " +
            $"rsi=0x{priority:X16} rdx=0x{resultAddress:X16} rcx=0x{ctx[CpuRegister.Rcx]:X16} " +
            $"r8=0x{ctx[CpuRegister.R8]:X16} r9=0x{ctx[CpuRegister.R9]:X16} ret=0x{returnRip:X16}");
        TraceReadableQword(ctx, operation, "rsi", priority);
        TraceReadableQword(ctx, operation, "rdx", resultAddress);
        TraceReadableQword(ctx, operation, "rcx", ctx[CpuRegister.Rcx]);
        TraceReadableQword(ctx, operation, "r8", ctx[CpuRegister.R8]);
    }

    private static void TraceReadableQword(CpuContext ctx, string operation, string name, ulong address)
    {
        if (address == 0 || !ctx.TryReadUInt64(address, out var value))
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][TRACE] apr.{operation}.{name}: addr=0x{address:X16} q0=0x{value:X16}");
    }
}
