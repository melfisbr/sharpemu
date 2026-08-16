// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Network;

public static class Http2Exports
{
    private const int Http2ErrorInvalidId = unchecked((int)0x80436004);
    private const int Http2ErrorInvalidArgument = unchecked((int)0x80436016);

    private static readonly ConcurrentDictionary<int, Http2Context> _contexts = new();
    private static readonly ConcurrentDictionary<int, Http2Template> _templates = new();
    private static readonly ConcurrentDictionary<int, Http2Request> _requests = new();
    private static int _nextContextId;
    private static int _nextTemplateId = 0x4000;
    private static int _nextRequestId = 0x5000;

    private sealed record Http2Context(int NetId, int SslId, ulong PoolSize, int MaxRequests);
    private sealed record Http2Template(int ContextId, ulong UserAgentAddress);
    private sealed class Http2Request { public Http2Request(int templateId) { TemplateId = templateId; } public int TemplateId { get; } public bool Completed { get; set; } }

    [SysAbiExport(
        Nid = "3JCe3lCbQ8A",
        ExportName = "sceHttp2Init",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceHttp2")]
    public static int Http2Init(CpuContext ctx)
    {
        var netId = unchecked((int)ctx[CpuRegister.Rdi]);
        var sslId = unchecked((int)ctx[CpuRegister.Rsi]);
        var poolSize = ctx[CpuRegister.Rdx];
        var maxRequests = unchecked((int)ctx[CpuRegister.Rcx]);

        if (poolSize == 0 || maxRequests <= 0)
        {
            return ctx.SetReturn(Http2ErrorInvalidArgument);
        }

        var id = Interlocked.Increment(ref _nextContextId);
        _contexts[id] = new Http2Context(netId, sslId, poolSize, maxRequests);

        TraceHttp2("init", id, unchecked((ulong)netId), unchecked((ulong)sslId), poolSize, unchecked((ulong)maxRequests));
        ctx[CpuRegister.Rax] = unchecked((ulong)id);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "YiBUtz-pGkc",
        ExportName = "sceHttp2Term",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceHttp2")]
    public static int Http2Term(CpuContext ctx)
    {
        var id = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!_contexts.TryRemove(id, out _))
        {
            return ctx.SetReturn(Http2ErrorInvalidId);
        }

        TraceHttp2("term", id, 0, 0, 0, 0);
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "+wCt7fCijgk", ExportName = "sceHttp2CreateTemplate", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp2")]
    public static int Http2CreateTemplate(CpuContext ctx)
    {
        var contextId = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!_contexts.ContainsKey(contextId)) return ctx.SetReturn(Http2ErrorInvalidId);
        var id = Interlocked.Increment(ref _nextTemplateId);
        _templates[id] = new Http2Template(contextId, ctx[CpuRegister.Rsi]);
        return ctx.SetReturn(id);
    }

    [SysAbiExport(Nid = "pDom5-078DA", ExportName = "sceHttp2DeleteTemplate", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp2")]
    public static int Http2DeleteTemplate(CpuContext ctx) => _templates.TryRemove(unchecked((int)ctx[CpuRegister.Rdi]), out _) ? ctx.SetReturn(0) : ctx.SetReturn(Http2ErrorInvalidId);

    [SysAbiExport(Nid = "mmyOCxQMVYQ", ExportName = "sceHttp2CreateRequestWithURL", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp2")]
    public static int Http2CreateRequestWithUrl(CpuContext ctx)
    {
        var templateId = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!_templates.ContainsKey(templateId)) return ctx.SetReturn(Http2ErrorInvalidId);
        if (ctx[CpuRegister.Rdx] == 0) return ctx.SetReturn(Http2ErrorInvalidArgument);
        var id = Interlocked.Increment(ref _nextRequestId);
        _requests[id] = new Http2Request(templateId);
        return ctx.SetReturn(id);
    }

    [SysAbiExport(Nid = "nrPfOE8TQu0", ExportName = "sceHttp2AddRequestHeader", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp2")]
    public static int Http2AddRequestHeader(CpuContext ctx) => _requests.ContainsKey(unchecked((int)ctx[CpuRegister.Rdi])) ? ctx.SetReturn(0) : ctx.SetReturn(Http2ErrorInvalidId);

    [SysAbiExport(Nid = "A+NVAFu4eCg", ExportName = "sceHttp2SendRequestAsync", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp2")]
    public static int Http2SendRequestAsync(CpuContext ctx)
    {
        if (!_requests.TryGetValue(unchecked((int)ctx[CpuRegister.Rdi]), out var request)) return ctx.SetReturn(Http2ErrorInvalidId);
        request.Completed = true;
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "MOp-AUhdfi8", ExportName = "sceHttp2WaitAsync", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp2")]
    public static int Http2WaitAsync(CpuContext ctx) => _requests.ContainsKey(unchecked((int)ctx[CpuRegister.Rdi])) ? ctx.SetReturn(0) : ctx.SetReturn(Http2ErrorInvalidId);

    private static void TraceHttp2(string operation, int id, ulong arg0, ulong arg1, ulong arg2, ulong arg3)
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_HTTP2"), "1", StringComparison.Ordinal))
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][TRACE] http2.{operation} id={id} arg0=0x{arg0:X16} arg1=0x{arg1:X16} arg2=0x{arg2:X16} arg3=0x{arg3:X16}");
    }
}
