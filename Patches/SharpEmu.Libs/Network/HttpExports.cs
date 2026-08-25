// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System.Collections.Concurrent;

namespace SharpEmu.Libs.Network;

public static class HttpExports
{
    private const int HttpErrorInvalidId = unchecked((int)0x80431100);
    private const int HttpErrorInvalidValue = unchecked((int)0x804311FE);
    private const int HttpErrorInvalidAddress = unchecked((int)0x804311FF);

    private static readonly ConcurrentDictionary<int, HttpContext> Contexts = new();
    private static readonly ConcurrentDictionary<int, HttpTemplate> Templates = new();
    private static readonly ConcurrentDictionary<int, HttpConnection> Connections = new();
    private static readonly ConcurrentDictionary<int, HttpRequest> Requests = new();
    private static int _nextContextId;
    private static int _nextTemplateId = 0x1000;
    private static int _nextConnectionId = 0x2000;
    private static int _nextRequestId = 0x3000;

    private sealed record HttpContext(int NetMemoryId, int SslContextId, ulong PoolSize);

    private sealed record HttpTemplate(int ContextId, ulong UserAgentAddress, int HttpVersion, bool AutoProxyConfig);

    private sealed record HttpConnection(int TemplateId, ulong UrlAddress, bool KeepAlive);

    private sealed class HttpRequest
    {
        public HttpRequest(int connectionId, int method, ulong urlAddress, ulong contentLength)
        {
            ConnectionId = connectionId;
            Method = method;
            UrlAddress = urlAddress;
            ContentLength = contentLength;
        }

        public int ConnectionId { get; }
        public int Method { get; }
        public ulong UrlAddress { get; }
        public ulong ContentLength { get; }
        public bool Chunked { get; set; }
        public bool Aborted { get; set; }
        public bool Completed { get; set; }
        public int StatusCode { get; set; }
        public int EpollId { get; set; }
    }

    [SysAbiExport(
        Nid = "A9cVMUtEp4Y",
        ExportName = "sceHttpInit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceHttp")]
    public static int HttpInit(CpuContext ctx)
    {
        var netMemoryId = unchecked((int)ctx[CpuRegister.Rdi]);
        var sslContextId = unchecked((int)ctx[CpuRegister.Rsi]);
        var poolSize = ctx[CpuRegister.Rdx];
        if (poolSize == 0)
        {
            return ctx.SetReturn(HttpErrorInvalidValue);
        }

        var id = Interlocked.Increment(ref _nextContextId);
        Contexts[id] = new HttpContext(netMemoryId, sslContextId, poolSize);
        TraceHttp("init", id, unchecked((ulong)netMemoryId), unchecked((ulong)sslContextId), poolSize, 0);
        ctx[CpuRegister.Rax] = unchecked((ulong)id);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "0gYjPTR-6cY",
        ExportName = "sceHttpCreateTemplate",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceHttp")]
    public static int HttpCreateTemplate(CpuContext ctx)
    {
        var contextId = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!Contexts.ContainsKey(contextId))
        {
            return ctx.SetReturn(HttpErrorInvalidId);
        }

        var userAgentAddress = ctx[CpuRegister.Rsi];
        var httpVersion = unchecked((int)ctx[CpuRegister.Rdx]);
        var autoProxyConfig = ctx[CpuRegister.Rcx] != 0;
        var id = Interlocked.Increment(ref _nextTemplateId);
        Templates[id] = new HttpTemplate(contextId, userAgentAddress, httpVersion, autoProxyConfig);
        TraceHttp("create_template", id, unchecked((ulong)contextId), userAgentAddress, unchecked((ulong)httpVersion), autoProxyConfig ? 1UL : 0UL);
        ctx[CpuRegister.Rax] = unchecked((ulong)id);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "4I8vEpuEhZ8",
        ExportName = "sceHttpDeleteTemplate",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceHttp")]
    public static int HttpDeleteTemplate(CpuContext ctx)
    {
        var templateId = unchecked((int)ctx[CpuRegister.Rdi]);
        return Templates.TryRemove(templateId, out _)
            ? ctx.SetReturn(0)
            : ctx.SetReturn(HttpErrorInvalidId);
    }

    [SysAbiExport(
        Nid = "Ik-KpLTlf7Q",
        ExportName = "sceHttpTerm",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceHttp")]
    public static int HttpTerm(CpuContext ctx)
    {
        var contextId = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!Contexts.TryRemove(contextId, out _))
        {
            return ctx.SetReturn(HttpErrorInvalidId);
        }

        foreach (var pair in Templates)
        {
            if (pair.Value.ContextId == contextId)
            {
                Templates.TryRemove(pair.Key, out _);
            }
        }

        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "qgxDBjorUxs", ExportName = "sceHttpCreateConnectionWithURL", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpCreateConnectionWithUrl(CpuContext ctx)
    {
        var templateId = unchecked((int)ctx[CpuRegister.Rdi]);
        var url = ctx[CpuRegister.Rsi];
        if (!Templates.ContainsKey(templateId)) return ctx.SetReturn(HttpErrorInvalidId);
        if (url == 0) return ctx.SetReturn(HttpErrorInvalidAddress);
        var id = Interlocked.Increment(ref _nextConnectionId);
        Connections[id] = new HttpConnection(templateId, url, ctx[CpuRegister.Rdx] != 0);
        TraceHttp("create_connection", id, unchecked((ulong)templateId), url, ctx[CpuRegister.Rdx], 0);
        return ctx.SetReturn(id);
    }

    [SysAbiExport(Nid = "P6A3ytpsiYc", ExportName = "sceHttpDeleteConnection", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpDeleteConnection(CpuContext ctx)
    {
        var id = unchecked((int)ctx[CpuRegister.Rdi]);
        if (!Connections.TryRemove(id, out _)) return ctx.SetReturn(HttpErrorInvalidId);
        foreach (var request in Requests)
            if (request.Value.ConnectionId == id) Requests.TryRemove(request.Key, out _);
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "Aeu5wVKkF9w", ExportName = "sceHttpCreateRequestWithURL", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpCreateRequestWithUrl(CpuContext ctx)
    {
        var connectionId = unchecked((int)ctx[CpuRegister.Rdi]);
        var url = ctx[CpuRegister.Rdx];
        if (!Connections.ContainsKey(connectionId)) return ctx.SetReturn(HttpErrorInvalidId);
        if (url == 0) return ctx.SetReturn(HttpErrorInvalidAddress);
        var id = Interlocked.Increment(ref _nextRequestId);
        Requests[id] = new HttpRequest(connectionId, unchecked((int)ctx[CpuRegister.Rsi]), url, ctx[CpuRegister.Rcx]);
        TraceHttp("create_request", id, unchecked((ulong)connectionId), ctx[CpuRegister.Rsi], url, ctx[CpuRegister.Rcx]);
        return ctx.SetReturn(id);
    }

    [SysAbiExport(Nid = "qe7oZ+v4PWA", ExportName = "sceHttpDeleteRequest", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpDeleteRequest(CpuContext ctx) => Requests.TryRemove(unchecked((int)ctx[CpuRegister.Rdi]), out _) ? ctx.SetReturn(0) : ctx.SetReturn(HttpErrorInvalidId);

    [SysAbiExport(Nid = "hvG6GfBMXg8", ExportName = "sceHttpAbortRequest", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpAbortRequest(CpuContext ctx)
    {
        if (!Requests.TryGetValue(unchecked((int)ctx[CpuRegister.Rdi]), out var request)) return ctx.SetReturn(HttpErrorInvalidId);
        request.Aborted = true;
        request.Completed = true;
        request.StatusCode = 499;
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "EY28T2bkN7k", ExportName = "sceHttpAddRequestHeader", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpAddRequestHeader(CpuContext ctx)
    {
        if (!Requests.ContainsKey(unchecked((int)ctx[CpuRegister.Rdi]))) return ctx.SetReturn(HttpErrorInvalidId);
        if (ctx[CpuRegister.Rsi] == 0 || ctx[CpuRegister.Rdx] == 0) return ctx.SetReturn(HttpErrorInvalidAddress);
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "1e2BNwI-XzE", ExportName = "sceHttpSendRequest", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpSendRequest(CpuContext ctx)
    {
        if (!Requests.TryGetValue(unchecked((int)ctx[CpuRegister.Rdi]), out var request)) return ctx.SetReturn(HttpErrorInvalidId);
        if (request.Aborted) return ctx.SetReturn(HttpErrorInvalidValue);
        request.Completed = true;
        request.StatusCode = 204; // deterministic offline response; never performs host I/O
        TraceHttp("send_request", unchecked((int)ctx[CpuRegister.Rdi]), ctx[CpuRegister.Rsi], ctx[CpuRegister.Rdx], 0, 0);
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "qISjDHrxONc", ExportName = "sceHttpWaitRequest", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpWaitRequest(CpuContext ctx) => Requests.ContainsKey(unchecked((int)ctx[CpuRegister.Rdi])) ? ctx.SetReturn(0) : ctx.SetReturn(HttpErrorInvalidId);

    [SysAbiExport(Nid = "0a2TBNfE3BU", ExportName = "sceHttpGetStatusCode", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpGetStatusCode(CpuContext ctx)
    {
        if (!Requests.TryGetValue(unchecked((int)ctx[CpuRegister.Rdi]), out var request)) return ctx.SetReturn(HttpErrorInvalidId);
        var output = ctx[CpuRegister.Rsi];
        if (output == 0 || !ctx.TryWriteUInt32(output, unchecked((uint)request.StatusCode))) return ctx.SetReturn(HttpErrorInvalidAddress);
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "yuO2H2Uvnos", ExportName = "sceHttpGetResponseContentLength", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpGetResponseContentLength(CpuContext ctx)
    {
        if (!Requests.TryGetValue(unchecked((int)ctx[CpuRegister.Rdi]), out _)) return ctx.SetReturn(HttpErrorInvalidId);
        var output = ctx[CpuRegister.Rsi];
        if (output == 0 || !ctx.TryWriteUInt64(output, 0)) return ctx.SetReturn(HttpErrorInvalidAddress);
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "PDxS48xGQLs", ExportName = "sceHttpSetChunkedTransferEnabled", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpSetChunkedTransferEnabled(CpuContext ctx)
    {
        if (!Requests.TryGetValue(unchecked((int)ctx[CpuRegister.Rdi]), out var request)) return ctx.SetReturn(HttpErrorInvalidId);
        request.Chunked = ctx[CpuRegister.Rsi] != 0;
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "-xm7kZQNpHI", ExportName = "sceHttpSetEpoll", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpSetEpoll(CpuContext ctx)
    {
        if (!Requests.TryGetValue(unchecked((int)ctx[CpuRegister.Rdi]), out var request)) return ctx.SetReturn(HttpErrorInvalidId);
        request.EpollId = unchecked((int)ctx[CpuRegister.Rsi]);
        return ctx.SetReturn(0);
    }

    [SysAbiExport(Nid = "htyBOoWeS58", ExportName = "sceHttpsSetSslCallback", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceHttp")]
    public static int HttpsSetSslCallback(CpuContext ctx) => Requests.ContainsKey(unchecked((int)ctx[CpuRegister.Rdi])) ? ctx.SetReturn(0) : ctx.SetReturn(HttpErrorInvalidId);

    private static void TraceHttp(string operation, int id, ulong arg0, ulong arg1, ulong arg2, ulong arg3)
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_HTTP"), "1", StringComparison.Ordinal))
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][TRACE] http.{operation} id={id} arg0=0x{arg0:X16} arg1=0x{arg1:X16} arg2=0x{arg2:X16} arg3=0x{arg3:X16}");
    }
}
