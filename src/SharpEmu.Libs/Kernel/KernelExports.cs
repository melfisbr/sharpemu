// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System.Threading;

namespace SharpEmu.Libs.Kernel;

public static class KernelExports
{
    private static readonly object _cxaGate = new();
    private static readonly List<CxaDestructorEntry> _cxaDestructors = new();
    private static readonly object _coredumpGate = new();
    private static ulong _coredumpHandler;
    private static ulong _coredumpHandlerContext;

    // SHARPEMU_DBFZ_PTHREAD_JOIN_COOPERATIVE_V1_8_37
    private static long _pthreadJoinCooperativeCountV1837;
    private static long _pthreadJoinHostFallbackCountV1837;
    private static readonly bool _traceJoinWaiterV1837 =
        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_DBFZ_WAITER_TRACE"), "1", StringComparison.Ordinal);

    private sealed class PthreadJoinBlockWaiterV1837 : IGuestThreadBlockWaiter
    {
        private readonly IGuestThreadScheduler _scheduler;
        private readonly CpuContext _context;
        private readonly ulong _targetThread;
        private readonly ulong _returnValueAddress;

        public PthreadJoinBlockWaiterV1837(IGuestThreadScheduler scheduler, CpuContext context, ulong targetThread, ulong returnValueAddress)
        {
            _scheduler = scheduler;
            _context = context;
            _targetThread = targetThread;
            _returnValueAddress = returnValueAddress;
        }

        public bool TryWake()
        {
            foreach (var thread in _scheduler.SnapshotThreads())
            {
                if (thread.ThreadHandle == _targetThread)
                {
                    return string.Equals(thread.State, "Exited", StringComparison.Ordinal) ||
                        string.Equals(thread.State, "Faulted", StringComparison.Ordinal);
                }
            }
            return true;
        }

        public int Resume()
        {
            if (!_scheduler.TryJoinThread(_context, _targetThread, out var returnValue, out var error))
            {
                return string.Equals(error, "thread cannot join itself", StringComparison.Ordinal)
                    ? (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT
                    : (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
            }
            if (_returnValueAddress != 0 && !_context.TryWriteUInt64(_returnValueAddress, returnValue))
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }
    }

    private static bool ShouldTraceJoinWaiterV1837(long count) =>
        _traceJoinWaiterV1837 && (count <= 32 || (count & (count - 1)) == 0);

    // V76.3.8: DBFZ render-exit chain compatibility.
    // V76.3.7 proved RTHeartBeat can complete once guest TLS/runtime cleanup is
    // bypassed for that title-scoped thread. The next pthread_join target is
    // RenderThread 0, which reaches the same pthread_exit stall. Keep the old
    // RTHeartBeat compatibility and extend the bypass only to RenderThread.
    private const string DbfzRtHeartbeatExitCompatEnvV7637 =
        "SHARPEMU_DBFZ_RT_HEARTBEAT_EXIT_COMPAT";
    private const string DbfzRenderThreadExitCompatEnvV7638 =
        "SHARPEMU_DBFZ_RENDER_THREAD_EXIT_COMPAT";

    private static bool IsDbfzThreadExitCompatEnabledV7638(
        out string threadName,
        out string cleanupKind)
    {
        threadName = string.Empty;
        cleanupKind = string.Empty;
        if (!KernelMemoryCompatExports.IsConfiguredApplicationTitle("PPSA09790"))
        {
            return false;
        }

        var currentHandle = GuestThreadExecution.CurrentGuestThreadHandle;
        if (currentHandle == 0 || GuestThreadExecution.Scheduler is not { } scheduler)
        {
            return false;
        }

        foreach (var snapshot in scheduler.SnapshotThreads())
        {
            if (snapshot.ThreadHandle != currentHandle)
            {
                continue;
            }

            threadName = snapshot.Name;
            if (threadName.StartsWith("RTHeartBeat", StringComparison.Ordinal) &&
                !string.Equals(
                    Environment.GetEnvironmentVariable(DbfzRtHeartbeatExitCompatEnvV7637),
                    "0",
                    StringComparison.Ordinal))
            {
                cleanupKind = "rt-heartbeat";
                return true;
            }

            if (threadName.StartsWith("RenderThread", StringComparison.Ordinal) &&
                !string.Equals(
                    Environment.GetEnvironmentVariable(DbfzRenderThreadExitCompatEnvV7638),
                    "0",
                    StringComparison.Ordinal))
            {
                cleanupKind = "render-thread";
                return true;
            }

            return false;
        }

        return false;
    }

    private static int CompletePthreadExitV7638(
        CpuContext ctx,
        string reason,
        ulong value,
        bool posix)
    {
        if (IsDbfzThreadExitCompatEnabledV7638(out var threadName, out var cleanupKind))
        {
            var handle = GuestThreadExecution.CurrentGuestThreadHandle;
            Console.Error.WriteLine(
                $"[DBFZ-PTHREAD-EXIT][V76.3.8] action=direct-entry-exit " +
                $"api={(posix ? "pthread_exit" : "scePthreadExit")} " +
                $"thread=0x{handle:X16} name='{threadName}' value=0x{value:X16} " +
                $"cleanup={cleanupKind}-bypass scope=PPSA09790");
            GuestThreadExecution.RequestCurrentEntryExit(reason, value);
            ctx[CpuRegister.Rax] = value;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        KernelPthreadExtendedCompatExports.RunThreadLocalDestructors(ctx);
        KernelMemoryCompatExports.RunThreadDtors(ctx);
        GuestThreadExecution.RequestCurrentEntryExit(reason, value);
        ctx[CpuRegister.Rax] = value;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private readonly record struct CxaDestructorEntry(
        ulong Function,
        ulong Argument,
        ulong ModuleHandle);

    [SysAbiExport(
        Nid = "WB66evu8bsU",
        ExportName = "sceKernelGetCompiledSdkVersion",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelGetCompiledSdkVersion(CpuContext ctx)
    {
        _ = ctx;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "8zLSfEfW5AU",
        ExportName = "sceCoredumpRegisterCoredumpHandler",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceCoredump")]
    public static int CoredumpRegisterHandler(CpuContext ctx)
    {
        lock (_coredumpGate)
        {
            _coredumpHandler = ctx[CpuRegister.Rdi];
            _coredumpHandlerContext = ctx[CpuRegister.Rsi];
        }

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "uMei1W9uyNo",
        ExportName = "exit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int Exit(CpuContext ctx)
    {
        var status = unchecked((int)ctx[CpuRegister.Rdi]);
        Console.Error.WriteLine($"[LOADER][INFO] exit(status={status})");
        RunCxaFinalizersV6501(ctx, 0, "exit");
        GuestThreadExecution.RequestCurrentEntryExit("exit", status);
        ctx[CpuRegister.Rax] = unchecked((ulong)status);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "XKRegsFpEpk",
        ExportName = "catchReturnFromMain",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CatchReturnFromMain(CpuContext ctx)
    {
        var status = unchecked((int)ctx[CpuRegister.Rdi]);
        Console.Error.WriteLine($"[LOADER][INFO] catchReturnFromMain(status={status})");
        GuestThreadExecution.RequestCurrentEntryExit("catchReturnFromMain", status);
        ctx[CpuRegister.Rax] = unchecked((ulong)status);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
    Nid = "bzQExy189ZI",
    ExportName = "_init_env",
    Target = Generation.Gen4 | Generation.Gen5,
    LibraryName = "libc")]
// SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC
public static int InitEnv(CpuContext ctx)
{
    const ulong entryAddressOffset = 0x110;
    var parameters = ctx[CpuRegister.Rdi];
    ulong argcAndPadding = 0;
    ulong argv0 = 0;
    ulong entryAddress = 0;
    var headerKnown = parameters != 0 && ctx.TryReadUInt64(parameters, out argcAndPadding);
    var argc = headerKnown ? (uint)(argcAndPadding & 0xFFFF_FFFFUL) : 0U;
    var parsed = headerKnown && argc <= 33 && ctx.TryReadUInt64(parameters + 0x08, out argv0);
    var fullEntryKnown = parsed &&
        ctx.TryReadUInt64(parameters + entryAddressOffset, out entryAddress) &&
        entryAddress >= 0x0000_0000_0001_0000UL;

    if (parsed)
    {
        var entryText = fullEntryKnown ? $"0x{entryAddress:X16}" : "unavailable";
        Console.Error.WriteLine(
            $"[V74.0.21][ENTRY_ABI] init_env_hle_fallback params=0x{parameters:X16} " +
            $"argc={argc} argv0=0x{argv0:X16} entry={entryText} full={fullEntryKnown}");
    }
    else
    {
        Console.Error.WriteLine(
            $"[V74.0.21][ENTRY_ABI] init_env_hle_fallback params=0x{parameters:X16} malformed=True");
    }

    ctx[CpuRegister.Rax] = 0;
    return (int)OrbisGen2Result.ORBIS_GEN2_OK;
}

    [SysAbiExport(
        Nid = "8G2LB+A3rzg",
        ExportName = "atexit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Atexit(CpuContext ctx)
    {
        var function = ctx[CpuRegister.Rdi];
        if (function != 0)
        {
            lock (_cxaGate)
            {
                _cxaDestructors.Add(new CxaDestructorEntry(function, 0, 0));
            }
        }

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "tsvEmnenz48",
        ExportName = "__cxa_atexit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CxaAtexit(CpuContext ctx)
    {
        var destructorFunction = ctx[CpuRegister.Rdi];
        var destructorArgument = ctx[CpuRegister.Rsi];
        var moduleHandle = ctx[CpuRegister.Rdx];
        if (destructorFunction == 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        lock (_cxaGate)
        {
            _cxaDestructors.Add(new CxaDestructorEntry(
                destructorFunction,
                destructorArgument,
                moduleHandle));
        }

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "H2e8t5ScQGc",
        ExportName = "__cxa_finalize",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int CxaFinalize(CpuContext ctx)
    {
        RunCxaFinalizersV6501(ctx, ctx[CpuRegister.Rdi], "__cxa_finalize");
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    // V65.0.1: execute registered C/C++ finalizers.
    private static void RunCxaFinalizersV6501(
        CpuContext ctx,
        ulong moduleHandle,
        string reason)
    {
        var pending = new List<CxaDestructorEntry>();
        lock (_cxaGate)
        {
            for (var i = _cxaDestructors.Count - 1; i >= 0; i--)
            {
                var entry = _cxaDestructors[i];
                if (moduleHandle != 0 && entry.ModuleHandle != moduleHandle)
                {
                    continue;
                }

                pending.Add(entry);
                _cxaDestructors.RemoveAt(i);
            }
        }

        if (pending.Count == 0)
        {
            return;
        }

        var scheduler = GuestThreadExecution.Scheduler;
        if (scheduler is null)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] cxa.finalize scheduler_unavailable reason={reason} count={pending.Count}");
            return;
        }

        foreach (var entry in pending)
        {
            if (!scheduler.TryCallGuestFunction(
                    ctx,
                    entry.Function,
                    entry.Argument,
                    0,
                    0,
                    0,
                    0,
                    reason,
                    out _,
                    out var error))
            {
                Console.Error.WriteLine(
                    $"[LOADER][WARN] cxa.finalizer_failed reason={reason} " +
                    $"fn=0x{entry.Function:X16} arg=0x{entry.Argument:X16} " +
                    $"dso=0x{entry.ModuleHandle:X16} error={error ?? "unknown"}");
            }
        }
    }

    [SysAbiExport(
        Nid = "kbw4UHHSYy0",
        ExportName = "__pthread_cxa_finalize",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int PthreadCxaFinalize(CpuContext ctx)
    {
        _ = ctx;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "6Z83sYWFlA8",
        ExportName = "_exit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int UnderscoreExit(CpuContext ctx)
    {
        _ = ctx;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "Ac86z8q7T8A",
        ExportName = "sceKernelExitSblock",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelExitSblock(CpuContext ctx)
    {
        _ = ctx;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "6UgtwV+0zb4",
        ExportName = "scePthreadCreate",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int PthreadCreate(CpuContext ctx)
        => PthreadCreateCore(ctx, ctx[CpuRegister.R8]);

    private static int PthreadCreateCore(CpuContext ctx, ulong nameAddress)
    {
        var threadIdAddress = ctx[CpuRegister.Rdi];
        var attrAddress = ctx[CpuRegister.Rsi];
        var entryAddress = ctx[CpuRegister.Rdx];
        var argument = ctx[CpuRegister.Rcx];
        var name = nameAddress == 0 ? string.Empty : ReadCString(ctx, nameAddress, 256);
        var threadHandle = KernelPthreadState.CreateThreadHandle(name);
        KernelPthreadExtendedCompatExports.GetThreadStartScheduling(
            ctx,
            attrAddress,
            out var priority,
            out var affinityMask);
        KernelPthreadExtendedCompatExports.RegisterThreadStart(
            threadHandle,
            name,
            priority,
            affinityMask);
        if (threadIdAddress != 0 && !ctx.TryWriteUInt64(threadIdAddress, threadHandle))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        if (ShouldTracePthread())
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] pthread_create: out=0x{threadIdAddress:X16} attr=0x{attrAddress:X16} " +
                $"entry=0x{entryAddress:X16} arg=0x{argument:X16} name_ptr=0x{nameAddress:X16} " +
                $"name='{name}' priority={priority} affinity=0x{affinityMask:X} -> thread=0x{threadHandle:X16}");
        }

        var scheduler = GuestThreadExecution.Scheduler;
        if (scheduler is not null && entryAddress != 0)
        {
            var request = new GuestThreadStartRequest(
                threadHandle,
                entryAddress,
                argument,
                attrAddress,
                name,
                priority,
                affinityMask);
            if (!scheduler.TryStartThread(ctx, request, out var error))
            {
                Console.Error.WriteLine(
                    $"[LOADER][ERROR] pthread_create: failed to schedule guest thread '{name}' entry=0x{entryAddress:X16}: {error}");
                ctx[CpuRegister.Rax] = unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN);
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN;
            }
        }

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "OxhIB8LB-PQ",
        ExportName = "pthread_create",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int PosixPthreadCreate(CpuContext ctx)
    {
        return PthreadCreateCore(ctx, nameAddress: 0);
    }

    [SysAbiExport(
        Nid = "Jmi+9w9u0E4",
        ExportName = "pthread_create_name_np",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int PosixPthreadCreateNameNp(CpuContext ctx)
    {
        return PthreadCreateCore(ctx, ctx[CpuRegister.R8]);
    }

    [SysAbiExport(
        Nid = "3kg7rT0NQIs",
        ExportName = "scePthreadExit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int PthreadExit(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        // Run cleanup on the still-executable thread before unwinding it.
        return CompletePthreadExitV7638(ctx, "scePthreadExit", value, posix: false);
    }

    [SysAbiExport(
        Nid = "FJrT5LuUBAU",
        ExportName = "pthread_exit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libScePosix")]
    public static int PosixPthreadExit(CpuContext ctx)
    {
        var value = ctx[CpuRegister.Rdi];
        return CompletePthreadExitV7638(ctx, "pthread_exit", value, posix: true);
    }

    [SysAbiExport(
        Nid = "onNY9Byn-W8",
        ExportName = "scePthreadJoin",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int PthreadJoin(CpuContext ctx)
    {
        var threadId = ctx[CpuRegister.Rdi];
        var returnValueAddress = ctx[CpuRegister.Rsi];

        if (ShouldTracePthread())
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] pthread_join: thread=0x{threadId:X16} retval_out=0x{returnValueAddress:X16}");
        }

        if (GuestThreadExecution.CanCooperativelyBlockCurrentThread() &&
            GuestThreadExecution.Scheduler is { } cooperativeScheduler &&
            threadId != GuestThreadExecution.CurrentGuestThreadHandle)
        {
            var targetKnownV1837 = false;
            var targetPendingV1837 = false;
            foreach (var snapshotV1837 in cooperativeScheduler.SnapshotThreads())
            {
                if (snapshotV1837.ThreadHandle != threadId)
                {
                    continue;
                }
                targetKnownV1837 = true;
                targetPendingV1837 = !string.Equals(snapshotV1837.State, "Exited", StringComparison.Ordinal) &&
                    !string.Equals(snapshotV1837.State, "Faulted", StringComparison.Ordinal);
                break;
            }
            if (targetKnownV1837 && targetPendingV1837)
            {
                var joinWakeKeyV1837 = $"pthread_join:{threadId:X16}";
                if (GuestThreadExecution.RequestCurrentThreadBlock(
                        ctx,
                        "scePthreadJoin",
                        joinWakeKeyV1837,
                        new PthreadJoinBlockWaiterV1837(cooperativeScheduler, ctx, threadId, returnValueAddress)))
                {
                    var countV1837 = Interlocked.Increment(ref _pthreadJoinCooperativeCountV1837);
                    if (ShouldTraceJoinWaiterV1837(countV1837))
                    {
                        Console.Error.WriteLine($"[DBFZ-WAIT-1837] join_coop n={countV1837} waiter=0x{GuestThreadExecution.CurrentGuestThreadHandle:X16} target=0x{threadId:X16}");
                    }
                    ctx[CpuRegister.Rax] = 0;
                    return (int)OrbisGen2Result.ORBIS_GEN2_OK;
                }
            }
        }

        var hostJoinV1837 = Interlocked.Increment(ref _pthreadJoinHostFallbackCountV1837);
        if (ShouldTraceJoinWaiterV1837(hostJoinV1837))
        {
            Console.Error.WriteLine($"[DBFZ-WAIT-1837] join_host n={hostJoinV1837} waiter=0x{GuestThreadExecution.CurrentGuestThreadHandle:X16} target=0x{threadId:X16}");
        }

        var returnValue = 0UL;
        if (GuestThreadExecution.Scheduler is { } scheduler &&
            !scheduler.TryJoinThread(ctx, threadId, out returnValue, out var error))
        {
            Console.Error.WriteLine(
                $"[LOADER][ERROR] pthread_join: thread=0x{threadId:X16}: {error}");
            var result = string.Equals(
                error,
                "thread cannot join itself",
                StringComparison.Ordinal)
                ? OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT
                : OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
            ctx[CpuRegister.Rax] = unchecked((ulong)(int)result);
            return (int)result;
        }

        if (returnValueAddress != 0 &&
            !ctx.TryWriteUInt64(returnValueAddress, returnValue))
        {
            ctx[CpuRegister.Rax] =
                unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "h9CcP3J0oVM",
        ExportName = "pthread_join",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int PosixPthreadJoin(CpuContext ctx)
    {
        return PthreadJoin(ctx);
    }

    [SysAbiExport(
        Nid = "wuCroIGjt2g",
        ExportName = "open",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int Open(CpuContext ctx) => KernelMemoryCompatExports.PosixOpen(ctx);

    [SysAbiExport(
        Nid = "1G3lF1Gg1k8",
        ExportName = "sceKernelOpen",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelOpen(CpuContext ctx)

    {

        // SHARPEMU_DBFZ_KERNEL_OPEN_DIRECTORY_COMPAT_V1_5_0

        // sceKernelOpen and _open share the same path/flag/fd machinery. Keeping a

        // second implementation here caused O_DIRECTORY-only DBFZ probes

        // (flags=0x00020000) to return EINVAL even though the compatibility open

        // correctly treats them as read-only directory opens.

        var flags = unchecked((int)ctx[CpuRegister.Rsi]);

        var result = KernelMemoryCompatExports.KernelOpenUnderscore(ctx);



        if (flags == 0x00020000)

        {

            var rax = ctx[CpuRegister.Rax];

            Console.Error.WriteLine(

                $"[LOADER][TRACE] dbfz.kernel_open_directory flags=0x{flags:X8} " +

                $"mode=0x{unchecked((uint)ctx[CpuRegister.Rdx]):X8} result=0x{unchecked((uint)result):X8} rax=0x{rax:X16}");

        }



        return result;

    }

    [SysAbiExport(
        Nid = "EMutwaQ34Jo",
        ExportName = "perror",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Perror(CpuContext ctx)
    {
        ulong sPtr = ctx[CpuRegister.Rdi];

        string msg;
        if (sPtr == 0)
        {
            msg = "perror(NULL)";
        }
        else
        {
            msg = ReadCString(ctx, sPtr, 2048);
            msg = $"perror(\"{msg}\")";
        }

        Console.WriteLine(msg);

        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static string ReadCString(CpuContext ctx, ulong address, int maxLen)
    {
        Span<byte> buf = stackalloc byte[maxLen];
        Span<byte> one = stackalloc byte[1];
        var len = 0;
        while (len < buf.Length)
        {
            if (!ctx.Memory.TryRead(address + (ulong)len, one))
                return len == 0 ? $"<unreadable 0x{address:X16}>" : System.Text.Encoding.UTF8.GetString(buf[..len]);

            if (one[0] == 0)
                break;

            buf[len++] = one[0];
        }

        try { return System.Text.Encoding.UTF8.GetString(buf[..len]); }
        catch { return System.Text.Encoding.ASCII.GetString(buf[..len]); }
    }

    private static bool ShouldTracePthread()
    {
        return string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_PTHREADS"), "1", StringComparison.Ordinal);
    }

    [SysAbiExport(
        Nid = "L1SBTkC+Cvw",
        ExportName = "abort",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libc")]
    public static int Abort(CpuContext ctx)
    {
        // Route through the same graceful guest-entry-exit path as exit(): letting the call
        // fall through to the host's native abort() does not unwind the guest thread cleanly.
        Console.Error.WriteLine("[LOADER][INFO] abort() called by guest - terminating");
        GuestThreadExecution.RequestCurrentEntryExit("abort", -1);
        ctx[CpuRegister.Rax] = unchecked((ulong)(-1L));
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
    Nid = "tU5e3f9gSiU",
    ExportName = "sceKernelIsTrinityMode",
    Target = Generation.Gen4 | Generation.Gen5,
    LibraryName = "libKernel")]
    public static int KernelIsTrinityMode(CpuContext ctx)
    {
        ctx[CpuRegister.Rax] = 0;

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
    Nid = "DLORcroUqbc",
    ExportName = "sceKernelGetOpenPsId",
    Target = Generation.Gen4 | Generation.Gen5,
    LibraryName = "libKernel")]
    public static int KernelGetOpenPsId(CpuContext ctx)
    {
        ulong bufferPtr = ctx[CpuRegister.Rdi];

        if (bufferPtr == 0)
        {
            ctx[CpuRegister.Rax] = unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);

            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        Span<byte> openPsId = stackalloc byte[16];

        if (!ctx.Memory.TryWrite(bufferPtr, openPsId))
        {
            ctx[CpuRegister.Rax] = unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        ctx[CpuRegister.Rax] = 0;

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }
}
