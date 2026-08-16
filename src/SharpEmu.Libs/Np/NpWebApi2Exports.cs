// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;

namespace SharpEmu.Libs.Np;

public static class NpWebApi2Exports
{
    private const int NpWebApi2ErrorInvalidArgument = unchecked((int)0x80553402);

    private static int _initialized;
    private static int _nextLibraryContextHandle;
    private static int _nextPushEventHandle;
    private static int _nextUserContextHandle = 1000;
    private static readonly object _contextGate = new();
    private static readonly HashSet<int> _libraryContexts = [];
    private static readonly HashSet<int> _userContexts = [];
    private static readonly HashSet<int> _requests = [];
    private static readonly HashSet<int> _pushFilters = [];
    private static readonly HashSet<int> _pushHandles = [];
    private static readonly HashSet<int> _pushContexts = [];
    private static int _nextRequestHandle = 0x2000;
    private static int _nextPushContextHandle = 0x3000;

    [SysAbiExport(
        Nid = "+o9816YQhqQ",
        ExportName = "sceNpWebApi2Initialize",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2Initialize(CpuContext ctx)
    {
        var httpContextId = unchecked((int)ctx[CpuRegister.Rdi]);
        var poolSize = ctx[CpuRegister.Rsi];

        if (httpContextId <= 0 || poolSize == 0)
        {
            return ctx.SetReturn(NpWebApi2ErrorInvalidArgument);
        }

        var libraryContextId = CreateLibraryContextId();
        Interlocked.Exchange(ref _initialized, 1);
        TraceNpWebApi2("init", httpContextId, poolSize);
        return ctx.SetReturn(libraryContextId);
    }

    [SysAbiExport(
        Nid = "MsaFhR+lPE4",
        ExportName = "sceNpWebApi2PushEventCreateFilter",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2PushEventCreateFilter(CpuContext ctx)
    {
        var libraryContextId = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!IsValidLibraryContextId(libraryContextId))
        {
            return ctx.SetReturn(NpWebApi2ErrorInvalidArgument);
        }

        var filterHandle = Interlocked.Increment(ref _nextPushEventHandle);
        lock (_contextGate) _pushFilters.Add(filterHandle);
        TraceNpWebApi2("push-event-create-filter", libraryContextId, (ulong)filterHandle);
        return ctx.SetReturn(filterHandle);
    }

    [SysAbiExport(
        Nid = "WV1GwM32NgY",
        ExportName = "sceNpWebApi2PushEventCreateHandle",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2InitializeAlt(CpuContext ctx)
    {
        var libraryContextId = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!IsValidLibraryContextId(libraryContextId))
        {
            return ctx.SetReturn(NpWebApi2ErrorInvalidArgument);
        }

        var handle = CreatePushEventHandle();
        lock (_contextGate) _pushHandles.Add(handle);
        Interlocked.Exchange(ref _initialized, 1);
        TraceNpWebApi2("init-alt", libraryContextId, 0);
        return ctx.SetReturn(handle);
    }

    [SysAbiExport(
        Nid = "sk54bi6FtYM",
        ExportName = "sceNpWebApi2CreateUserContext",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2CreateUserContext(CpuContext ctx)
    {
        var libraryContextId = unchecked((int)ctx[CpuRegister.Rdi]);
        var userId = unchecked((int)ctx[CpuRegister.Rsi]);

        TraceNpWebApi2(
            "create-user-context",
            libraryContextId,
            unchecked((uint)userId));

        if (Volatile.Read(ref _initialized) == 0 ||
            !IsValidLibraryContextId(libraryContextId) ||
            userId == -1)
        {
            return ctx.SetReturn(NpWebApi2ErrorInvalidArgument);
        }

        var userContextId = Interlocked.Increment(ref _nextUserContextHandle);
        lock (_contextGate) _userContexts.Add(userContextId);
        return ctx.SetReturn(userContextId);
    }

    [SysAbiExport(Nid = "3EI-OSJ65Xc", ExportName = "sceNpWebApi2CreateRequest", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2CreateRequest(CpuContext ctx)
    {
        var userContext = unchecked((int)ctx[CpuRegister.Rdi]); lock (_contextGate) if (!_userContexts.Contains(userContext)) return ctx.SetReturn(NpWebApi2ErrorInvalidArgument);
        var id = Interlocked.Increment(ref _nextRequestHandle); lock (_contextGate) _requests.Add(id); return ctx.SetReturn(id);
    }

    [SysAbiExport(Nid = "vvzWO-DvG1s", ExportName = "sceNpWebApi2DeleteRequest", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2DeleteRequest(CpuContext ctx) { lock (_contextGate) return ctx.SetReturn(_requests.Remove(unchecked((int)ctx[CpuRegister.Rdi])) ? 0 : NpWebApi2ErrorInvalidArgument); }

    [SysAbiExport(Nid = "9X9+cneTGUU", ExportName = "sceNpWebApi2DeleteUserContext", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2DeleteUserContext(CpuContext ctx) { lock (_contextGate) return ctx.SetReturn(_userContexts.Remove(unchecked((int)ctx[CpuRegister.Rdi])) ? 0 : NpWebApi2ErrorInvalidArgument); }

    [SysAbiExport(Nid = "NNVf18SlbT8", ExportName = "sceNpWebApi2PushEventCreatePushContext", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int PushEventCreatePushContext(CpuContext ctx)
    {
        var library = unchecked((int)ctx[CpuRegister.Rdi]); if (!IsValidLibraryContextId(library)) return ctx.SetReturn(NpWebApi2ErrorInvalidArgument);
        var id = Interlocked.Increment(ref _nextPushContextHandle); lock (_contextGate) _pushContexts.Add(id); return ctx.SetReturn(id);
    }

    [SysAbiExport(Nid = "KJdPcOGmK58", ExportName = "sceNpWebApi2PushEventDeleteFilter", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int PushEventDeleteFilter(CpuContext ctx) { lock (_contextGate) return ctx.SetReturn(_pushFilters.Remove(unchecked((int)ctx[CpuRegister.Rdi])) ? 0 : NpWebApi2ErrorInvalidArgument); }

    [SysAbiExport(Nid = "fIATVMo4Y1w", ExportName = "sceNpWebApi2PushEventDeleteHandle", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int PushEventDeleteHandle(CpuContext ctx) { lock (_contextGate) return ctx.SetReturn(_pushHandles.Remove(unchecked((int)ctx[CpuRegister.Rdi])) ? 0 : NpWebApi2ErrorInvalidArgument); }

    [SysAbiExport(Nid = "QafxeZM3WK4", ExportName = "sceNpWebApi2PushEventDeletePushContext", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int PushEventDeletePushContext(CpuContext ctx) { lock (_contextGate) return ctx.SetReturn(_pushContexts.Remove(unchecked((int)ctx[CpuRegister.Rdi])) ? 0 : NpWebApi2ErrorInvalidArgument); }

    [SysAbiExport(
        Nid = "bEvXpcEk200",
        ExportName = "sceNpWebApi2Terminate",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2Terminate(CpuContext ctx)
    {
        var libraryContextId = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!IsValidLibraryContextId(libraryContextId))
        {
            return ctx.SetReturn(NpWebApi2ErrorInvalidArgument);
        }

        RemoveLibraryContextId(libraryContextId);
        TraceNpWebApi2("term", libraryContextId, 0);
        return ctx.SetReturn(0);
    }

    private static int CreateLibraryContextId()
    {
        var handle = Interlocked.Increment(ref _nextLibraryContextHandle);
        lock (_contextGate)
        {
            _libraryContexts.Add(handle);
        }

        return handle;
    }

    private static int CreatePushEventHandle()
    {
        return Interlocked.Increment(ref _nextPushEventHandle);
    }

    private static bool IsValidLibraryContextId(int libraryContextId)
    {
        if (libraryContextId <= 0 || libraryContextId >= 0x8000)
        {
            return false;
        }

        lock (_contextGate)
        {
            return _libraryContexts.Contains(libraryContextId);
        }
    }

    private static void RemoveLibraryContextId(int libraryContextId)
    {
        lock (_contextGate)
        {
            _libraryContexts.Remove(libraryContextId);
            if (_libraryContexts.Count == 0)
            {
                Interlocked.Exchange(ref _initialized, 0);
            }
        }
    }

    private static void TraceNpWebApi2(string operation, int id, ulong arg0)
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_NP_WEB_API2"), "1", StringComparison.Ordinal))
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][TRACE] npwebapi2.{operation} id={id} arg0=0x{arg0:X16} initialized={Volatile.Read(ref _initialized)}");
    }

// SHARPEMU_DBFZ_NPWEBAPI2_PARTIAL_V1_8_12_3 hOnIlcGrO6g
    [SysAbiExport(Nid = "hOnIlcGrO6g", ExportName = "sceNpWebApi2PushEventUnregisterCallback", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2PushEventUnregisterCallbackV18123(CpuContext ctx)
    {
        var userContextId = unchecked((int)ctx[CpuRegister.Rdi]);
        var registrationHandle = unchecked((int)ctx[CpuRegister.Rsi]);
        if (userContextId <= 0 || registrationHandle <= 0) return ctx.SetReturn(unchecked((int)0x80553402));
        return ctx.SetReturn(0);
    }

// SHARPEMU_DBFZ_NPWEBAPI2_PARTIAL_V1_8_12_3 fY3QqeNkF8k
    private static int _dbfzV18123NextCallbackHandle = 0x4000;
    [SysAbiExport(Nid = "fY3QqeNkF8k", ExportName = "sceNpWebApi2PushEventRegisterCallback", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpWebApi2")]
    public static int NpWebApi2PushEventRegisterCallbackV18123(CpuContext ctx)
    {
        var userContextId = unchecked((int)ctx[CpuRegister.Rdi]);
        var filterHandle = unchecked((int)ctx[CpuRegister.Rsi]);
        var callback = ctx[CpuRegister.Rdx];
        if (userContextId <= 0 || filterHandle <= 0 || callback == 0) return ctx.SetReturn(unchecked((int)0x80553402));
        return ctx.SetReturn(Interlocked.Increment(ref _dbfzV18123NextCallbackHandle));
    }
}
