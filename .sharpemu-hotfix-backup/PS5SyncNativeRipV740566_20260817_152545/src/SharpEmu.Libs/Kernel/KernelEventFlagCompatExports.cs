// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using SharpEmu.HLE;
using SharpEmu.Libs.Fiber;

namespace SharpEmu.Libs.Kernel;

public static class KernelEventFlagCompatExports
{
    private const int MaxEventFlagNameLength = 31;
    private const int HostWaitPumpMilliseconds = 1;
    private const uint AttrThreadFifo = 0x01;
    private const uint AttrThreadPriority = 0x02;
    private const uint AttrSingle = 0x10;
    private const uint AttrMulti = 0x20;
    private const uint WaitAnd = 0x01;
    private const uint WaitOr = 0x02;
    private const uint ClearAll = 0x10;
    private const uint ClearPattern = 0x20;

    private static readonly ConcurrentDictionary<ulong, EventFlagState> _eventFlags = new();
    private static long _nextEventFlagHandle = 1;

    // Cached once: gating every call site avoids building the interpolated
    // trace string (and FormatFrameChain/FormatGuestWaitObject) when disabled.
    private static readonly bool _traceEventFlag = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_LOG_EVENT_FLAG"), "1", StringComparison.Ordinal);

    // [V74.0.56.5.1][PS5SYNC_EVENT_PRODUCER_AUDIT]
    // V56.4 proves the final e_entry stall is a real wait on the first
    // PS5SyncEvent object (handle 0x2 in that run), not on the busy 0x21
    // worker event. Track the real PS5SyncEvent lifecycle without changing
    // bits, wake policy, return values, or wait semantics.
    private static readonly bool _tracePs5SyncEventV7405651 = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_TRACE_PS5SYNC_EVENT"),
        "1",
        StringComparison.Ordinal);
    private static readonly int _ps5SyncSnapshotSecondsV7405651 =
        int.TryParse(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_PS5SYNC_SNAPSHOT_SECONDS"),
            out var parsedPs5SyncSnapshotSecondsV7405651)
            ? Math.Max(1, parsedPs5SyncSnapshotSecondsV7405651)
            : 5;
    private static long _nextEventFlagCreateOrdinalV7405651;
    private static long _primaryPs5SyncEventHandleV7405651;

    private sealed class EventFlagState
    {
        public required string Name { get; init; }
        public required uint Attributes { get; init; }
        public required long CreateOrdinalV7405651 { get; init; }
        public ulong Bits { get; set; }
        public int WaitingThreads { get; set; }
        public long WaitCountV7405651;
        public long SetCountV7405651;
        public long ClearCountV7405651;
        public long PollCountV7405651;
        public long CancelCountV7405651;
        public long DeleteCountV7405651;
        public object Gate { get; } = new();
    }

    [SysAbiExport(
        Nid = "BpFoboUJoZU",
        ExportName = "sceKernelCreateEventFlag",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelCreateEventFlag(CpuContext ctx)
    {
        var outAddress = ctx[CpuRegister.Rdi];
        var nameAddress = ctx[CpuRegister.Rsi];
        var attributes = unchecked((uint)ctx[CpuRegister.Rdx]);
        var initialPattern = ctx[CpuRegister.Rcx];
        var optionAddress = ctx[CpuRegister.R8];

        if (outAddress == 0 ||
            nameAddress == 0 ||
            optionAddress != 0 ||
            !IsValidAttributes(attributes))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        if (!TryReadNullTerminatedUtf8(ctx, nameAddress, MaxEventFlagNameLength + 1, out var name))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        if (Encoding.UTF8.GetByteCount(name) > MaxEventFlagNameLength)
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        var handle = unchecked((ulong)Interlocked.Increment(ref _nextEventFlagHandle));
        var createOrdinalV7405651 =
            Interlocked.Increment(ref _nextEventFlagCreateOrdinalV7405651);
        var eventStateV7405651 = new EventFlagState
        {
            Name = name,
            Attributes = attributes,
            CreateOrdinalV7405651 = createOrdinalV7405651,
            Bits = initialPattern,
        };
        _eventFlags[handle] = eventStateV7405651;

        if (!ctx.TryWriteUInt64(outAddress, handle))
        {
            _eventFlags.TryRemove(handle, out _);
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        if (string.Equals(name, "PS5SyncEvent", StringComparison.Ordinal))
        {
            _ = Interlocked.CompareExchange(
                ref _primaryPs5SyncEventHandleV7405651,
                unchecked((long)handle),
                0L);
            TracePs5SyncLifecycleV7405651(
                "create",
                handle,
                eventStateV7405651,
                operationOrdinal: createOrdinalV7405651,
                pattern: initialPattern,
                bitsBefore: initialPattern,
                bitsAfter: initialPattern,
                returnRip: GetCurrentReturnRip(),
                schedulerWakeCount: 0);
        }

        if (_traceEventFlag) TraceEventFlag($"create handle=0x{handle:X16} name='{name}' attr=0x{attributes:X2} bits=0x{initialPattern:X16}");
        return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
    }

    [SysAbiExport(
        Nid = "8mql9OcQnd4",
        ExportName = "sceKernelDeleteEventFlag",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelDeleteEventFlag(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        if (!_eventFlags.TryRemove(handle, out var state))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        var operationOrdinalV7405651 =
            Interlocked.Increment(ref state.DeleteCountV7405651);
        ulong bitsV7405651;
        lock (state.Gate)
        {
            bitsV7405651 = state.Bits;
            Monitor.PulseAll(state.Gate);
        }

        if (ShouldTracePs5SyncOperationV7405651(
                handle,
                state,
                operationOrdinalV7405651))
        {
            TracePs5SyncLifecycleV7405651(
                "delete",
                handle,
                state,
                operationOrdinalV7405651,
                pattern: 0,
                bitsBefore: bitsV7405651,
                bitsAfter: bitsV7405651,
                returnRip: GetCurrentReturnRip(),
                schedulerWakeCount: 0);
        }

        if (_traceEventFlag) TraceEventFlag($"delete handle=0x{handle:X16} name='{state.Name}'");
        return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
    }

    [SysAbiExport(
        Nid = "IOnSvHzqu6A",
        ExportName = "sceKernelSetEventFlag",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelSetEventFlag(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        var pattern = ctx[CpuRegister.Rsi];
        var returnRip = GetCurrentReturnRip();
        if (!_eventFlags.TryGetValue(handle, out var state))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        var operationOrdinalV7405651 =
            Interlocked.Increment(ref state.SetCountV7405651);
        ulong bitsBeforeV7405651;
        ulong bitsAfterV7405651;
        lock (state.Gate)
        {
            bitsBeforeV7405651 = state.Bits;
            state.Bits |= pattern;
            bitsAfterV7405651 = state.Bits;
            Monitor.PulseAll(state.Gate);
            if (_traceEventFlag) TraceEventFlag($"set handle=0x{handle:X16} pattern=0x{pattern:X16} bits=0x{state.Bits:X16} ret=0x{returnRip:X16}");
        }

        var schedulerWakeCountV7405651 =
            GuestThreadExecution.Scheduler?.WakeBlockedThreads(
                GetEventFlagWakeKey(handle)) ?? 0;
        if (ShouldTracePs5SyncOperationV7405651(
                handle,
                state,
                operationOrdinalV7405651))
        {
            TracePs5SyncLifecycleV7405651(
                "set",
                handle,
                state,
                operationOrdinalV7405651,
                pattern,
                bitsBeforeV7405651,
                bitsAfterV7405651,
                returnRip,
                schedulerWakeCountV7405651);
        }

        return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
    }

    [SysAbiExport(
        Nid = "7uhBFWRAS60",
        ExportName = "sceKernelClearEventFlag",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelClearEventFlag(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        var pattern = ctx[CpuRegister.Rsi];
        if (!_eventFlags.TryGetValue(handle, out var state))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        var operationOrdinalV7405651 =
            Interlocked.Increment(ref state.ClearCountV7405651);
        ulong bitsBeforeV7405651;
        ulong bitsAfterV7405651;
        lock (state.Gate)
        {
            bitsBeforeV7405651 = state.Bits;
            state.Bits &= pattern;
            bitsAfterV7405651 = state.Bits;
            if (_traceEventFlag) TraceEventFlag($"clear handle=0x{handle:X16} mask=0x{pattern:X16} bits=0x{state.Bits:X16}");
        }

        if (ShouldTracePs5SyncOperationV7405651(
                handle,
                state,
                operationOrdinalV7405651))
        {
            TracePs5SyncLifecycleV7405651(
                "clear",
                handle,
                state,
                operationOrdinalV7405651,
                pattern,
                bitsBeforeV7405651,
                bitsAfterV7405651,
                GetCurrentReturnRip(),
                schedulerWakeCount: 0);
        }

        return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
    }

    [SysAbiExport(
        Nid = "9lvj5DjHZiA",
        ExportName = "sceKernelPollEventFlag",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelPollEventFlag(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        var pattern = ctx[CpuRegister.Rsi];
        var waitMode = unchecked((uint)ctx[CpuRegister.Rdx]);
        var resultAddress = ctx[CpuRegister.Rcx];

        if (!_eventFlags.TryGetValue(handle, out var state))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        if (pattern == 0 || !IsValidWaitMode(waitMode))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        var operationOrdinalV7405651 =
            Interlocked.Increment(ref state.PollCountV7405651);
        lock (state.Gate)
        {
            var bitsBeforeV7405651 = state.Bits;
            if (!TryWriteResultPattern(ctx, resultAddress, state.Bits))
            {
                if (ShouldTracePs5SyncOperationV7405651(
                        handle,
                        state,
                        operationOrdinalV7405651))
                {
                    TracePs5SyncLifecycleV7405651(
                        "poll-memory-fault",
                        handle,
                        state,
                        operationOrdinalV7405651,
                        pattern,
                        bitsBeforeV7405651,
                        state.Bits,
                        GetCurrentReturnRip(),
                        schedulerWakeCount: 0);
                }
                return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            }

            if (!IsSatisfied(state.Bits, pattern, waitMode))
            {
                if (ShouldTracePs5SyncOperationV7405651(
                        handle,
                        state,
                        operationOrdinalV7405651))
                {
                    TracePs5SyncLifecycleV7405651(
                        "poll-busy",
                        handle,
                        state,
                        operationOrdinalV7405651,
                        pattern,
                        bitsBeforeV7405651,
                        state.Bits,
                        GetCurrentReturnRip(),
                        schedulerWakeCount: 0);
                }
                return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_BUSY);
            }

            ApplyClearMode(state, pattern, waitMode);
            if (_traceEventFlag) TraceEventFlag($"poll handle=0x{handle:X16} pattern=0x{pattern:X16} mode=0x{waitMode:X2} bits=0x{state.Bits:X16}");
            if (ShouldTracePs5SyncOperationV7405651(
                    handle,
                    state,
                    operationOrdinalV7405651))
            {
                TracePs5SyncLifecycleV7405651(
                    "poll-ok",
                    handle,
                    state,
                    operationOrdinalV7405651,
                    pattern,
                    bitsBeforeV7405651,
                    state.Bits,
                    GetCurrentReturnRip(),
                    schedulerWakeCount: 0);
            }
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
        }
    }

    [SysAbiExport(
        Nid = "JTvBflhYazQ",
        ExportName = "sceKernelWaitEventFlag",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelWaitEventFlag(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        var pattern = ctx[CpuRegister.Rsi];
        var waitMode = unchecked((uint)ctx[CpuRegister.Rdx]);
        var resultAddress = ctx[CpuRegister.Rcx];
        var timeoutAddress = ctx[CpuRegister.R8];
        var returnRip = GetCurrentReturnRip();

        if (!_eventFlags.TryGetValue(handle, out var state))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        if (pattern == 0 || !IsValidWaitMode(waitMode))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
        }

        uint timeoutUsec = 0;
        if (timeoutAddress != 0 && !TryReadUInt32(ctx, timeoutAddress, out timeoutUsec))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        var waitOrdinalV7405651 =
            Interlocked.Increment(ref state.WaitCountV7405651);
        var tracePs5SyncWaitV7405651 =
            ShouldTracePs5SyncOperationV7405651(
                handle,
                state,
                waitOrdinalV7405651);
        var primaryPs5SyncWaitV7405651 =
            IsPrimaryPs5SyncEventV7405651(handle, state);
        var waitStartTicksV7405651 = Stopwatch.GetTimestamp();
        var snapshotIntervalTicksV7405651 =
            (long)((double)_ps5SyncSnapshotSecondsV7405651 *
                Stopwatch.Frequency);
        var nextSnapshotTicksV7405651 =
            primaryPs5SyncWaitV7405651 &&
            !GuestThreadExecution.IsGuestThread
                ? waitStartTicksV7405651 +
                    snapshotIntervalTicksV7405651
                : long.MaxValue;

        if (tracePs5SyncWaitV7405651)
        {
            TracePs5SyncWaitV7405651(
                "wait-enter",
                handle,
                state,
                waitOrdinalV7405651,
                pattern,
                waitMode,
                timeoutAddress,
                timeoutUsec,
                returnRip,
                waitStartTicksV7405651);
        }

        Monitor.Enter(state.Gate);
        try
        {
            if (TryCompleteSatisfiedWait(ctx, state, pattern, waitMode, resultAddress, out var immediateWaitResult))
            {
                if (tracePs5SyncWaitV7405651)
                {
                    TracePs5SyncWaitV7405651(
                        "wait-return-immediate",
                        handle,
                        state,
                        waitOrdinalV7405651,
                        pattern,
                        waitMode,
                        timeoutAddress,
                        timeoutUsec,
                        returnRip,
                        waitStartTicksV7405651);
                }
                return SetReturn(ctx, immediateWaitResult);
            }

            // Timed waits block on a deadline instead of returning TIMED_OUT
            // immediately; a zero-microsecond timeout still degrades to an
            // instant poll because the deadline is already in the past.
            var deadline = timeoutAddress != 0
                ? GuestThreadExecution.ComputeDeadlineTimestamp(TimeSpan.FromMicroseconds(timeoutUsec))
                : 0;
            var hostDeadlineMs = timeoutAddress != 0
                ? Environment.TickCount64 + (timeoutUsec == 0
                    ? 0L
                    : Math.Max(1L, (timeoutUsec + 999L) / 1000L))
                : long.MaxValue;

            var currentGuestThread = GuestThreadExecution.CurrentGuestThreadHandle;
            var currentFiber = FiberExports.GetCurrentFiberAddressForDiagnostics(ctx);
            var managedThread = Environment.CurrentManagedThreadId;
            var blockedWaitResult = OrbisGen2Result.ORBIS_GEN2_OK;
            var satisfied = false;
            var requestedBlock = GuestThreadExecution.RequestCurrentThreadBlock(
                ctx,
                "sceKernelWaitEventFlag",
                GetEventFlagWakeKey(handle),
                () =>
                {
                    if (satisfied)
                    {
                        return (int)blockedWaitResult;
                    }

                    // Deadline expiry: report timeout with the current bits.
                    if (timeoutAddress != 0)
                    {
                        _ = TryWriteUInt32(ctx, timeoutAddress, 0);
                    }

                    _ = TryWriteResultPattern(ctx, resultAddress, state.Bits);
                    return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_TIMED_OUT;
                },
                () =>
                {
                    if (!TryPrepareBlockedWait(
                            ctx,
                            state,
                            pattern,
                            waitMode,
                            resultAddress,
                            out var preparedResult))
                    {
                        return false;
                    }

                    blockedWaitResult = preparedResult;
                    satisfied = true;
                    return true;
                },
                deadline);
            if (_traceEventFlag) TraceEventFlag($"wait-unsatisfied handle=0x{handle:X16} pattern=0x{pattern:X16} bits=0x{state.Bits:X16} guest_thread=0x{currentGuestThread:X16} fiber=0x{currentFiber:X16} managed={managedThread} block={requestedBlock} ret=0x{returnRip:X16} frames={FormatFrameChain(ctx)}");
            if (_traceEventFlag) TraceEventFlag($"wait-object handle=0x{handle:X16} name='{state.Name}' {FormatGuestWaitObject(ctx)}");
            if (!requestedBlock)
            {
                var scheduler = GuestThreadExecution.Scheduler;
                if (scheduler is null)
                {
                    if (tracePs5SyncWaitV7405651)
                    {
                        TracePs5SyncWaitV7405651(
                            "wait-no-scheduler",
                            handle,
                            state,
                            waitOrdinalV7405651,
                            pattern,
                            waitMode,
                            timeoutAddress,
                            timeoutUsec,
                            returnRip,
                            waitStartTicksV7405651);
                    }
                    return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN);
                }

                state.WaitingThreads++;
                if (_traceEventFlag) TraceEventFlag($"wait-pump handle=0x{handle:X16} pattern=0x{pattern:X16} waiters={state.WaitingThreads} guest_thread=0x{currentGuestThread:X16} fiber=0x{currentFiber:X16} managed={managedThread} ret=0x{returnRip:X16}");
                var releaseWaiter = true;
                try
                {
                    while (true)
                    {
                        Monitor.Exit(state.Gate);
                        try
                        {
                            scheduler.Pump(ctx, "sceKernelWaitEventFlag");

                            var nowTicksV7405651 = Stopwatch.GetTimestamp();
                            if (primaryPs5SyncWaitV7405651 &&
                                nowTicksV7405651 >= nextSnapshotTicksV7405651)
                            {
                                TracePs5SyncSchedulerSnapshotV7405651(
                                    handle,
                                    state.CreateOrdinalV7405651,
                                    waitOrdinalV7405651,
                                    waitStartTicksV7405651,
                                    scheduler);
                                nextSnapshotTicksV7405651 =
                                    nowTicksV7405651 +
                                    snapshotIntervalTicksV7405651;
                            }
                        }
                        finally
                        {
                            Monitor.Enter(state.Gate);
                        }

                        if (TryCompleteSatisfiedWait(ctx, state, pattern, waitMode, resultAddress, out var pumpedWaitResult))
                        {
                            state.WaitingThreads = Math.Max(0, state.WaitingThreads - 1);
                            releaseWaiter = false;
                            if (_traceEventFlag) TraceEventFlag($"wait-wake handle=0x{handle:X16} pattern=0x{pattern:X16} bits=0x{state.Bits:X16} waiters={state.WaitingThreads} ret=0x{returnRip:X16}");
                            if (tracePs5SyncWaitV7405651)
                            {
                                TracePs5SyncWaitV7405651(
                                    "wait-return-pump",
                                    handle,
                                    state,
                                    waitOrdinalV7405651,
                                    pattern,
                                    waitMode,
                                    timeoutAddress,
                                    timeoutUsec,
                                    returnRip,
                                    waitStartTicksV7405651);
                            }
                            return SetReturn(ctx, pumpedWaitResult);
                        }

                        var remaining = hostDeadlineMs - Environment.TickCount64;
                        if (timeoutAddress != 0 && remaining <= 0)
                        {
                            state.WaitingThreads = Math.Max(0, state.WaitingThreads - 1);
                            releaseWaiter = false;
                            _ = TryWriteUInt32(ctx, timeoutAddress, 0);
                            _ = TryWriteResultPattern(ctx, resultAddress, state.Bits);
                            if (_traceEventFlag) TraceEventFlag($"wait-timeout handle=0x{handle:X16} pattern=0x{pattern:X16} bits=0x{state.Bits:X16} ret=0x{returnRip:X16}");
                            if (tracePs5SyncWaitV7405651)
                            {
                                TracePs5SyncWaitV7405651(
                                    "wait-timeout",
                                    handle,
                                    state,
                                    waitOrdinalV7405651,
                                    pattern,
                                    waitMode,
                                    timeoutAddress,
                                    timeoutUsec,
                                    returnRip,
                                    waitStartTicksV7405651);
                            }
                            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_TIMED_OUT);
                        }

                        Monitor.Wait(state.Gate, (int)Math.Min(remaining, HostWaitPumpMilliseconds));
                    }
                }
                finally
                {
                    if (releaseWaiter)
                    {
                        state.WaitingThreads = Math.Max(0, state.WaitingThreads - 1);
                    }
                }
            }

            state.WaitingThreads++;
            if (_traceEventFlag) TraceEventFlag($"wait-block handle=0x{handle:X16} pattern=0x{pattern:X16} waiters={state.WaitingThreads} guest_thread=0x{currentGuestThread:X16} fiber=0x{currentFiber:X16} managed={managedThread} ret=0x{returnRip:X16}");
            if (tracePs5SyncWaitV7405651)
            {
                TracePs5SyncWaitV7405651(
                    "wait-cooperative-block",
                    handle,
                    state,
                    waitOrdinalV7405651,
                    pattern,
                    waitMode,
                    timeoutAddress,
                    timeoutUsec,
                    returnRip,
                    waitStartTicksV7405651);
            }
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
        }
        finally
        {
            Monitor.Exit(state.Gate);
        }
    }

    [SysAbiExport(
        Nid = "PZku4ZrXJqg",
        ExportName = "sceKernelCancelEventFlag",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelCancelEventFlag(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        var setPattern = ctx[CpuRegister.Rsi];
        var waiterCountAddress = ctx[CpuRegister.Rdx];
        if (!_eventFlags.TryGetValue(handle, out var state))
        {
            return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
        }

        var operationOrdinalV7405651 =
            Interlocked.Increment(ref state.CancelCountV7405651);
        ulong bitsBeforeV7405651;
        ulong bitsAfterV7405651;
        lock (state.Gate)
        {
            bitsBeforeV7405651 = state.Bits;
            if (waiterCountAddress != 0 &&
                !TryWriteUInt32(ctx, waiterCountAddress, unchecked((uint)state.WaitingThreads)))
            {
                return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            }

            state.Bits = setPattern;
            bitsAfterV7405651 = state.Bits;
            state.WaitingThreads = 0;
            Monitor.PulseAll(state.Gate);
            if (_traceEventFlag) TraceEventFlag(
                $"cancel handle=0x{handle:X16} bits=0x{setPattern:X16} " +
                $"guest_thread=0x{GuestThreadExecution.CurrentGuestThreadHandle:X16} ret=0x{GetCurrentReturnRip():X16}");
        }

        if (ShouldTracePs5SyncOperationV7405651(
                handle,
                state,
                operationOrdinalV7405651))
        {
            TracePs5SyncLifecycleV7405651(
                "cancel",
                handle,
                state,
                operationOrdinalV7405651,
                setPattern,
                bitsBeforeV7405651,
                bitsAfterV7405651,
                GetCurrentReturnRip(),
                schedulerWakeCount: 0);
        }

        return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_OK);
    }

    private static bool IsValidAttributes(uint attributes)
    {
        var queueMode = attributes & 0x0F;
        var threadMode = attributes & 0xF0;
        return (queueMode is 0 or AttrThreadFifo or AttrThreadPriority) &&
            (threadMode is 0 or AttrSingle or AttrMulti) &&
            (attributes & ~0x33u) == 0;
    }

    private static bool IsValidWaitMode(uint waitMode)
    {
        var condition = waitMode & 0x0F;
        var clearMode = waitMode & 0xF0;
        return condition is WaitAnd or WaitOr &&
            clearMode is 0 or ClearAll or ClearPattern &&
            (waitMode & ~0x33u) == 0;
    }

    private static bool IsSatisfied(ulong bits, ulong pattern, uint waitMode) =>
        (waitMode & 0x0F) == WaitAnd
            ? (bits & pattern) == pattern
            : (bits & pattern) != 0;

    private static void ApplyClearMode(EventFlagState state, ulong pattern, uint waitMode)
    {
        switch (waitMode & 0xF0)
        {
            case ClearAll:
                state.Bits = 0;
                break;
            case ClearPattern:
                state.Bits &= ~pattern;
                break;
        }
    }

    private static bool TryCompleteSatisfiedWait(
    CpuContext ctx,
    EventFlagState state,
    ulong pattern,
    uint waitMode,
    ulong resultAddress,
    out OrbisGen2Result result)
    {
        result = OrbisGen2Result.ORBIS_GEN2_OK;

        if (!IsSatisfied(state.Bits, pattern, waitMode))
        {
            return false;
        }

        if (!TryWriteResultPattern(ctx, resultAddress, state.Bits))
        {
            result = OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            return true;
        }

        ApplyClearMode(state, pattern, waitMode);
        return true;
    }

    private static bool TryPrepareBlockedWait(
        CpuContext ctx,
        EventFlagState state,
        ulong pattern,
        uint waitMode,
        ulong resultAddress,
        out OrbisGen2Result result)
    {
        lock (state.Gate)
        {
            result = OrbisGen2Result.ORBIS_GEN2_OK;
            if (!IsSatisfied(state.Bits, pattern, waitMode))
            {
                return false;
            }

            if (!TryWriteResultPattern(ctx, resultAddress, state.Bits))
            {
                result = OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }
            else
            {
                ApplyClearMode(state, pattern, waitMode);
            }

            state.WaitingThreads = Math.Max(0, state.WaitingThreads - 1);
            if (_traceEventFlag) TraceEventFlag(
                $"wait-wake pattern=0x{pattern:X16} mode=0x{waitMode:X2} bits=0x{state.Bits:X16} waiters={state.WaitingThreads}");
            return true;
        }
    }

    private static bool IsPs5SyncEventV7405651(EventFlagState state) =>
        _tracePs5SyncEventV7405651 &&
        string.Equals(
            state.Name,
            "PS5SyncEvent",
            StringComparison.Ordinal);

    private static bool IsPrimaryPs5SyncEventV7405651(
        ulong handle,
        EventFlagState state) =>
        IsPs5SyncEventV7405651(state) &&
        unchecked((long)handle) ==
            Volatile.Read(ref _primaryPs5SyncEventHandleV7405651);

    private static bool ShouldTracePs5SyncOperationV7405651(
        ulong handle,
        EventFlagState state,
        long operationOrdinal)
    {
        if (!IsPs5SyncEventV7405651(state))
        {
            return false;
        }

        if (IsPrimaryPs5SyncEventV7405651(handle, state))
        {
            return true;
        }

        return operationOrdinal <= 16 ||
            (operationOrdinal > 0 &&
             (operationOrdinal & (operationOrdinal - 1)) == 0);
    }

    private static void TracePs5SyncLifecycleV7405651(
        string evt,
        ulong handle,
        EventFlagState state,
        long operationOrdinal,
        ulong pattern,
        ulong bitsBefore,
        ulong bitsAfter,
        ulong returnRip,
        int schedulerWakeCount)
    {
        if (!IsPs5SyncEventV7405651(state))
        {
            return;
        }

        Console.Error.WriteLine(
            $"[V74.0.56.5.1][PS5SYNC_LIFECYCLE] " +
            $"ticks={Stopwatch.GetTimestamp()} event={evt} " +
            $"handle=0x{handle:X16} " +
            $"primary={(IsPrimaryPs5SyncEventV7405651(handle, state) ? 1 : 0)} " +
            $"create_n={state.CreateOrdinalV7405651} op_n={operationOrdinal} " +
            $"name='{state.Name}' attr=0x{state.Attributes:X2} " +
            $"pattern=0x{pattern:X16} " +
            $"bits_before=0x{bitsBefore:X16} " +
            $"bits_after=0x{bitsAfter:X16} " +
            $"waiters={state.WaitingThreads} " +
            $"guest_thread=0x{GuestThreadExecution.CurrentGuestThreadHandle:X16} " +
            $"fiber=0x{GuestThreadExecution.CurrentFiberAddress:X16} " +
            $"managed={Environment.CurrentManagedThreadId} " +
            $"scheduler_woken={schedulerWakeCount} " +
            $"ret=0x{returnRip:X16}");
    }

    private static void TracePs5SyncWaitV7405651(
        string evt,
        ulong handle,
        EventFlagState state,
        long waitOrdinal,
        ulong pattern,
        uint waitMode,
        ulong timeoutAddress,
        uint timeoutUsec,
        ulong returnRip,
        long waitStartTicks)
    {
        if (!IsPs5SyncEventV7405651(state))
        {
            return;
        }

        var nowTicks = Stopwatch.GetTimestamp();
        var elapsedMs =
            (nowTicks - waitStartTicks) * 1000.0 /
            Stopwatch.Frequency;
        Console.Error.WriteLine(
            $"[V74.0.56.5.1][PS5SYNC_WAIT] " +
            $"ticks={nowTicks} event={evt} " +
            $"handle=0x{handle:X16} " +
            $"primary={(IsPrimaryPs5SyncEventV7405651(handle, state) ? 1 : 0)} " +
            $"create_n={state.CreateOrdinalV7405651} wait_n={waitOrdinal} " +
            $"pattern=0x{pattern:X16} mode=0x{waitMode:X2} " +
            $"bits=0x{state.Bits:X16} waiters={state.WaitingThreads} " +
            $"timeout_ptr=0x{timeoutAddress:X16} timeout_us={timeoutUsec} " +
            $"guest_thread=0x{GuestThreadExecution.CurrentGuestThreadHandle:X16} " +
            $"fiber=0x{GuestThreadExecution.CurrentFiberAddress:X16} " +
            $"managed={Environment.CurrentManagedThreadId} " +
            $"elapsed_ms={elapsedMs:F3} ret=0x{returnRip:X16}");
    }

    private static void TracePs5SyncSchedulerSnapshotV7405651(
        ulong handle,
        long createOrdinal,
        long waitOrdinal,
        long waitStartTicks,
        IGuestThreadScheduler scheduler)
    {
        if (!_tracePs5SyncEventV7405651)
        {
            return;
        }

        var nowTicks = Stopwatch.GetTimestamp();
        var elapsedMs =
            (nowTicks - waitStartTicks) * 1000.0 /
            Stopwatch.Frequency;
        var snapshots = scheduler.SnapshotThreads();
        Console.Error.WriteLine(
            $"[V74.0.56.5.1][PS5SYNC_SNAPSHOT] " +
            $"ticks={nowTicks} handle=0x{handle:X16} " +
            $"create_n={createOrdinal} wait_n={waitOrdinal} " +
            $"elapsed_ms={elapsedMs:F3} threads={snapshots.Count}");

        foreach (var snapshot in snapshots)
        {
            Console.Error.WriteLine(
                $"[V74.0.56.5.1][PS5SYNC_THREAD] " +
                $"ticks={nowTicks} wait_n={waitOrdinal} " +
                $"handle=0x{snapshot.ThreadHandle:X16} " +
                $"name='{snapshot.Name}' state={snapshot.State} " +
                $"imports={snapshot.ImportCount} " +
                $"nid={snapshot.LastImportNid ?? "none"} " +
                $"ret=0x{snapshot.LastReturnRip:X16} " +
                $"block='{snapshot.BlockReason ?? "none"}'");
        }
    }

    private static string GetEventFlagWakeKey(ulong handle) =>
        $"event_flag:0x{handle:X16}";

    private static bool TryWriteResultPattern(CpuContext ctx, ulong address, ulong bits) =>
        address == 0 || ctx.TryWriteUInt64(address, bits);

    private static bool TryReadUInt32(CpuContext ctx, ulong address, out uint value)
    {
        Span<byte> buffer = stackalloc byte[sizeof(uint)];
        if (!ctx.Memory.TryRead(address, buffer))
        {
            value = 0;
            return false;
        }

        value = BinaryPrimitives.ReadUInt32LittleEndian(buffer);
        return true;
    }

    private static bool TryReadUInt64(CpuContext ctx, ulong address, out ulong value)
    {
        Span<byte> buffer = stackalloc byte[sizeof(ulong)];
        if (!ctx.Memory.TryRead(address, buffer))
        {
            value = 0;
            return false;
        }

        value = BinaryPrimitives.ReadUInt64LittleEndian(buffer);
        return true;
    }

    private static bool TryReadByte(CpuContext ctx, ulong address, out byte value)
    {
        Span<byte> buffer = stackalloc byte[1];
        if (!ctx.Memory.TryRead(address, buffer))
        {
            value = 0;
            return false;
        }

        value = buffer[0];
        return true;
    }

    private static bool TryWriteUInt32(CpuContext ctx, ulong address, uint value)
    {
        Span<byte> buffer = stackalloc byte[sizeof(uint)];
        BinaryPrimitives.WriteUInt32LittleEndian(buffer, value);
        return ctx.Memory.TryWrite(address, buffer);
    }

    private static bool TryReadNullTerminatedUtf8(CpuContext ctx, ulong address, int capacity, out string value)
    {
        var bytes = new byte[capacity];
        Span<byte> current = stackalloc byte[1];
        for (var index = 0; index < bytes.Length; index++)
        {
            if (!ctx.Memory.TryRead(address + (ulong)index, current))
            {
                value = string.Empty;
                return false;
            }

            if (current[0] == 0)
            {
                value = Encoding.UTF8.GetString(bytes, 0, index);
                return true;
            }

            bytes[index] = current[0];
        }

        value = Encoding.UTF8.GetString(bytes);
        return true;
    }

    private static int SetReturn(CpuContext ctx, OrbisGen2Result result)
    {
        var value = (int)result;
        ctx[CpuRegister.Rax] = unchecked((ulong)value);
        return value;
    }

    private static void TraceEventFlag(string message)
    {
        if (_traceEventFlag)
        {
            Console.Error.WriteLine($"[LOADER][TRACE] event_flag.{message}");
        }
    }

    private static ulong GetCurrentReturnRip() =>
        GuestThreadExecution.TryGetCurrentImportCallFrame(out var frame)
            ? frame.ReturnRip
            : 0UL;

    private static string FormatFrameChain(CpuContext ctx)
    {
        Span<ulong> returns = stackalloc ulong[4];
        var count = 0;
        var frame = ctx[CpuRegister.Rbp];
        for (var index = 0; index < returns.Length && frame != 0; index++)
        {
            if (!ctx.TryReadUInt64(frame, out var nextFrame) ||
                !ctx.TryReadUInt64(frame + sizeof(ulong), out var returnAddress))
            {
                break;
            }

            returns[count++] = returnAddress;
            if (nextFrame <= frame)
            {
                break;
            }

            frame = nextFrame;
        }

        return count switch
        {
            0 => "none",
            1 => $"0x{returns[0]:X16}",
            2 => $"0x{returns[0]:X16},0x{returns[1]:X16}",
            3 => $"0x{returns[0]:X16},0x{returns[1]:X16},0x{returns[2]:X16}",
            _ => $"0x{returns[0]:X16},0x{returns[1]:X16},0x{returns[2]:X16},0x{returns[3]:X16}",
        };
    }

    private static string FormatGuestWaitObject(CpuContext ctx)
    {
        var r12 = ctx[CpuRegister.R12];
        var r13 = ctx[CpuRegister.R13];
        var objectAddress = r12 != 0
            ? r12
            : r13 >= 0xA8
                ? r13 - 0xA8
                : 0;

        var builder = new StringBuilder(256);
        builder.Append($"r12=0x{r12:X16} r13=0x{r13:X16}");
        if (objectAddress == 0)
        {
            return builder.ToString();
        }

        builder.Append($" obj=0x{objectAddress:X16}");
        AppendUInt32(builder, ctx, objectAddress + 0x58, "o58");
        AppendUInt32(builder, ctx, objectAddress + 0x5C, "o5C");
        AppendUInt64(builder, ctx, objectAddress + 0x60, "o60");
        AppendByte(builder, ctx, objectAddress + 0x6C, "state6C");
        AppendByte(builder, ctx, objectAddress + 0x6D, "o6D");
        AppendByte(builder, ctx, objectAddress + 0xA0, "waitA0");
        AppendByte(builder, ctx, objectAddress + 0xA1, "stateA1");
        AppendByte(builder, ctx, objectAddress + 0xA2, "oA2");
        AppendUInt64(builder, ctx, objectAddress + 0xA8, "eventA8");
        if (r13 != 0)
        {
            AppendUInt64(builder, ctx, r13, "r13_0");
            AppendUInt64(builder, ctx, r13 + 8, "r13_8");
        }

        return builder.ToString();
    }

    private static void AppendByte(StringBuilder builder, CpuContext ctx, ulong address, string name)
    {
        if (TryReadByte(ctx, address, out var value))
        {
            builder.Append($" {name}=0x{value:X2}");
        }
    }

    private static void AppendUInt32(StringBuilder builder, CpuContext ctx, ulong address, string name)
    {
        if (TryReadUInt32(ctx, address, out var value))
        {
            builder.Append($" {name}=0x{value:X8}");
        }
    }

    private static void AppendUInt64(StringBuilder builder, CpuContext ctx, ulong address, string name)
    {
        if (TryReadUInt64(ctx, address, out var value))
        {
            builder.Append($" {name}=0x{value:X16}");
        }
    }
}
