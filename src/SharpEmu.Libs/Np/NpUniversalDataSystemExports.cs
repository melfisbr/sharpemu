// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System.Buffers.Binary;

namespace SharpEmu.Libs.Np;

public static class NpUniversalDataSystemExports
{
    private const int NpUniversalDataSystemErrorInvalidArgument = unchecked((int)0x80553102);
    private static readonly object _eventGate = new();
    private static readonly HashSet<int> _createdEvents = [];
    // V33: stateful UniversalDataSystem compatibility lifecycle.
    // Telemetry payloads remain local; no host analytics/network upload occurs.
    private static readonly HashSet<int> _contexts = [];
    private static readonly HashSet<int> _handles = [];
    private static readonly HashSet<int> _registeredContexts = [];
    private static readonly HashSet<int> _propertyArrays = [];
    private static readonly HashSet<int> _propertyObjects = [];
    private static int _initialized;
    private static int _nextContext;
    private static long _postedEventCount;
    private static int _nextHandle = 1;
    private static int _nextEvent = 1;
    private static int _nextProperty = 1;

    [SysAbiExport(Nid = "Hm7qubT3b70", ExportName = "sceNpUniversalDataSystemCreateEventPropertyArray", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpUniversalDataSystem")]
    public static int CreateEventPropertyArray(CpuContext ctx) => CreateProperty(ctx, _propertyArrays);

    [SysAbiExport(Nid = "s6W4Zl4Slgk", ExportName = "sceNpUniversalDataSystemCreateEventPropertyObject", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpUniversalDataSystem")]
    public static int CreateEventPropertyObject(CpuContext ctx) => CreateProperty(ctx, _propertyObjects);

    [SysAbiExport(Nid = "kKUH0Viib3c", ExportName = "sceNpUniversalDataSystemDestroyEventPropertyObject", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpUniversalDataSystem")]
    public static int DestroyEventPropertyObject(CpuContext ctx) { lock (_eventGate) _propertyObjects.Remove(unchecked((int)ctx[CpuRegister.Rdi])); return ctx.SetReturn(0, typeof(long)); }

    [SysAbiExport(Nid = "YE4dbtbz6OE", ExportName = "sceNpUniversalDataSystemEventPropertyObjectSetInt32", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpUniversalDataSystem")]
    public static int EventPropertyObjectSetInt32(CpuContext ctx)
    {
        var id = unchecked((int)ctx[CpuRegister.Rdi]); lock (_eventGate) if (!_propertyObjects.Contains(id)) return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long)); return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(Nid = "su7jW3VDDb4", ExportName = "sceNpUniversalDataSystemGetMemoryStat", Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libSceNpUniversalDataSystem")]
    public static int GetMemoryStat(CpuContext ctx)
    {
        var output = ctx[CpuRegister.Rdi]; if (output == 0) return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        Span<byte> stat = stackalloc byte[32]; stat.Clear(); BinaryPrimitives.WriteUInt64LittleEndian(stat, 32); BinaryPrimitives.WriteUInt64LittleEndian(stat[8..], (ulong)(_contexts.Count + _handles.Count + _createdEvents.Count));
        return ctx.Memory.TryWrite(output, stat) ? ctx.SetReturn(0, typeof(long)) : ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
    }

    private static int CreateProperty(CpuContext ctx, HashSet<int> target)
    {
        var output = ctx[CpuRegister.Rdi] != 0 ? ctx[CpuRegister.Rdi] : ctx[CpuRegister.Rsi]; if (output == 0) return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        var id = Interlocked.Increment(ref _nextProperty); lock (_eventGate) target.Add(id);
        if (!ctx.TryWriteInt32(output, id)) { lock (_eventGate) target.Remove(id); return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long)); }
        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "sjaobBgqeB4",
        ExportName = "sceNpUniversalDataSystemInitialize",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemInitialize(CpuContext ctx)
    {
        var parameterAddress = ctx[CpuRegister.Rdi];
        if (parameterAddress == 0)
        {
            return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        }

        Span<byte> parameters = stackalloc byte[16];
        if (!ctx.Memory.TryRead(parameterAddress, parameters))
        {
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
        }

        lock (_eventGate)
        {
            Volatile.Write(ref _initialized, 1);
        }
        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "5zBnau1uIEo",
        ExportName = "sceNpUniversalDataSystemCreateContext",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemCreateContext(CpuContext ctx)
    {
        var contextAddress = ctx[CpuRegister.Rdi];
        if (contextAddress == 0)
        {
            return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        }

        var contextId = Interlocked.Increment(ref _nextContext);
        lock (_eventGate)
        {
            _contexts.Add(contextId);
        }

        if (!ctx.TryWriteInt32(contextAddress, contextId))
        {
            lock (_eventGate) { _contexts.Remove(contextId); }
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
        }
        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "hT0IAEvN+M0",
        ExportName = "sceNpUniversalDataSystemCreateHandle",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemCreateHandle(CpuContext ctx)
    {
        var outAddress = ctx[CpuRegister.Rdi] != 0
            ? ctx[CpuRegister.Rdi]
            : ctx[CpuRegister.Rsi];
        if (outAddress == 0)
        {
            return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        }

        var handle = Interlocked.Increment(ref _nextHandle);
        lock (_eventGate)
        {
            _handles.Add(handle);
        }

        if (!ctx.TryWriteInt32(outAddress, handle))
        {
            lock (_eventGate) { _handles.Remove(handle); }
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
        }
        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "p+GcLqwpL9M",
        ExportName = "sceNpUniversalDataSystemCreateEvent",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemCreateEvent(CpuContext ctx)
    {
        var parameterAddress = ctx[CpuRegister.Rdi];
        if (parameterAddress == 0)
        {
            return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        }

        var eventId = Interlocked.Increment(ref _nextEvent);
        lock (_eventGate)
        {
            _createdEvents.Add(eventId);
        }

        if (ctx.TryWriteInt32(ctx[CpuRegister.Rdx], eventId, checkNil: true) ||
            ctx.TryWriteInt32(ctx[CpuRegister.Rcx], eventId, checkNil: true))
        {
            return ctx.SetReturn(0, typeof(long));
        }

        lock (_eventGate)
        {
            _createdEvents.Remove(eventId);
        }

        return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
    }

    [SysAbiExport(
        Nid = "wG+84pnNIuo",
        ExportName = "sceNpUniversalDataSystemDestroyEvent",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemDestroyEvent(CpuContext ctx)
    {
        var eventId = unchecked((int)ctx[CpuRegister.Rdi]);
        lock (_eventGate)
        {
            _createdEvents.Remove(eventId);
        }
        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "MfDb+4Nln64",
        ExportName = "sceNpUniversalDataSystemEventPropertyObjectSetString",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemEventPropertyObjectSetString(CpuContext ctx)
    {
        var propertyObjectAddress = ctx[CpuRegister.Rsi];
        var valueAddress = ctx[CpuRegister.Rdx];
        if (propertyObjectAddress == 0 || valueAddress == 0)
        {
            return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        }

        Span<byte> probe = stackalloc byte[1];
        return ctx.Memory.TryRead(propertyObjectAddress, probe) &&
               ctx.Memory.TryRead(valueAddress, probe)
            ? ctx.SetReturn(0, typeof(long))
            : ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
    }

    [SysAbiExport(
        Nid = "Wxbg5x3pTXA",
        ExportName = "sceNpUniversalDataSystemEventPropertyObjectSetArray",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemEventPropertyObjectSetArray(CpuContext ctx)
    {
        var propertyObjectAddress = ctx[CpuRegister.Rsi];
        var valueAddress = ctx[CpuRegister.Rdx];
        if (propertyObjectAddress == 0)
        {
            return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        }

        Span<byte> probe = stackalloc byte[1];
        if (!ctx.Memory.TryRead(propertyObjectAddress, probe))
        {
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
        }

        if (valueAddress != 0 && !ctx.Memory.TryRead(valueAddress, probe))
        {
            return ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
        }

        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "CzkKf7ahIyU",
        ExportName = "sceNpUniversalDataSystemPostEvent",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemPostEvent(CpuContext ctx)
    {
        // Different SDK revisions place the event id in different leading
        // scalar slots. Validate a known id when one is recognizable, while
        // preserving the established no-upload success behavior for opaque
        // telemetry payloads.
        var candidates = new[]
        {
            unchecked((int)ctx[CpuRegister.Rdi]),
            unchecked((int)ctx[CpuRegister.Rsi]),
            unchecked((int)ctx[CpuRegister.Rdx])
        };

        lock (_eventGate)
        {
            foreach (var candidate in candidates)
            {
                if (candidate > 0 && _createdEvents.Contains(candidate))
                {
                    Interlocked.Increment(ref _postedEventCount);
                    break;
                }
            }
        }

        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "tpFJ8LIKvPw",
        ExportName = "sceNpUniversalDataSystemRegisterContext",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemRegisterContext(CpuContext ctx)
    {
        var first = unchecked((int)ctx[CpuRegister.Rdi]);
        var second = unchecked((int)ctx[CpuRegister.Rsi]);

        lock (_eventGate)
        {
            if (_contexts.Contains(first))
            {
                _registeredContexts.Add(first);
            }
            else if (_contexts.Contains(second))
            {
                _registeredContexts.Add(second);
            }
        }

        return ctx.SetReturn(0, typeof(long));
    }

    [SysAbiExport(
        Nid = "AUIHb7jUX3I",
        ExportName = "sceNpUniversalDataSystemDestroyHandle",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemDestroyHandle(CpuContext ctx)
    {
        var handle = unchecked((int)ctx[CpuRegister.Rdi]);
        lock (_eventGate)
        {
            _handles.Remove(handle);
        }
        return ctx.SetReturn(0, typeof(long));
    }

    // Telemetry property setter (event property array, string value). We do not
    // upload analytics, so accept and drop it — matching the other Set* stubs.
    [SysAbiExport(
        Nid = "4llLk7YJRTE",
        ExportName = "sceNpUniversalDataSystemEventPropertyArraySetString",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceNpUniversalDataSystem")]
    public static int NpUniversalDataSystemEventPropertyArraySetString(CpuContext ctx)
    {
        var arrayAddress = ctx[CpuRegister.Rsi];
        var valueAddress = ctx[CpuRegister.Rdx];
        if (arrayAddress == 0 || valueAddress == 0)
        {
            return ctx.SetReturn(NpUniversalDataSystemErrorInvalidArgument, typeof(long));
        }

        Span<byte> probe = stackalloc byte[1];
        return ctx.Memory.TryRead(arrayAddress, probe) &&
               ctx.Memory.TryRead(valueAddress, probe)
            ? ctx.SetReturn(0, typeof(long))
            : ctx.SetReturn((int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT, typeof(long));
    }
    public static int NpUniversalDataSystemTerminateCore(CpuContext ctx)
    {
        lock (_eventGate)
        {
            _createdEvents.Clear();
            _contexts.Clear();
            _handles.Clear();
            _registeredContexts.Clear();
            _propertyArrays.Clear();
            _propertyObjects.Clear();
            Volatile.Write(ref _initialized, 0);
        }

        return ctx.SetReturn(0, typeof(long));
    }
}
