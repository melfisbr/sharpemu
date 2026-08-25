// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using SharpEmu.Libs.Agc;
using SharpEmu.Libs.Kernel;
using System.Buffers;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using Microsoft.Win32.SafeHandles;

namespace SharpEmu.Libs.Ampr;

public static class AmprExports
{
    private const int CommandBufferHeaderSize = 0x28;
    private const ulong CommandBufferSelfOffset = 0x00;
    private const ulong CommandBufferDataOffset = 0x08;
    private const ulong CommandBufferSizeOffset = 0x10;
    private const ulong CommandBufferAux0Offset = 0x18;
    private const ulong CommandBufferAux1Offset = 0x20;
    private const ulong ReadFileRecordSize = 0x30;
    private const ulong KernelEventQueueRecordSize = 0x30;
    private const ulong WriteAddressRecordSize = 0x20;
    // AMM commands carry six arguments after the command-buffer pointer.  A
    // 0x40-byte record stores type/opcode plus those six qwords exactly.
    private const ulong AmmRecordSize = 0x40;
    private const uint ReadFileRecordType = 1;
    private const uint KernelEventQueueRecordType = 2;
    private const uint WriteAddressRecordType = 3;
    private const uint AmmRecordType = 4;
    private const uint AmmOpcodeMap = 1;
    private const uint AmmOpcodeMapDirect = 2;
    private const uint AmmOpcodeMapAsPrt = 3;
    private const uint AmmOpcodeRemap = 4;
    private const uint AmmOpcodeRemapIntoPrt = 5;
    private const uint AmmOpcodeUnmap = 6;
    private const uint AmmOpcodeUnmapToPrt = 7;
    private static readonly ConcurrentDictionary<ulong, CommandBufferState> _commandBuffers = new();
    private static readonly bool _traceAmpr =
        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_AMPR"), "1", StringComparison.Ordinal);
    private static readonly bool _traceAmprReads =
        _traceAmpr ||
        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_AMPR_READS"), "1", StringComparison.Ordinal);
    private static long _v73016QueuedReadTraceCount;
    private static long _v73016CompletedReadTraceCount;
    private static long _v73016FailedReadTraceCount;

    // SHARPEMU_V74_0_56_27_1_APR_ASSET_AUDIT
    // Demon's Souls streams many title resources through APR, so open/stat
    // routing alone cannot prove whether CTXR/CMSH/CMAT/CSDR bytes are read.
    private static readonly bool _traceAprAssetReadsV74056271 =
        string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_TRACE_APR_ASSET_READS"),
            "1",
            StringComparison.Ordinal);

    private static readonly ConcurrentDictionary<string, long>
        _aprAssetReadCountsV74056271 =
            new(StringComparer.OrdinalIgnoreCase);

    // SHARPEMU_APR_ASYNC_SNAPSHOT_PIPELINE_V1_8_25
    private static long _v1825IoBytes;
    private static long _v1825HostReadTicks;
    private static long _v1825GuestWriteTicks;

    internal sealed class AprCommandBufferSubmissionSnapshot
    {
        public AprCommandBufferSubmissionSnapshot(
            ulong commandBuffer,
            ulong buffer,
            ulong writeOffset,
            byte[] records)
        {
            CommandBuffer = commandBuffer;
            Buffer = buffer;
            WriteOffset = writeOffset;
            Records = records;
        }

        public ulong CommandBuffer { get; }
        public ulong Buffer { get; }
        public ulong WriteOffset { get; }
        public byte[] Records { get; }
    }

    internal readonly record struct AprIoPerfSnapshot(
        long CompletedReadCount,
        long Bytes,
        long HostReadTicks,
        long GuestWriteTicks);

    private sealed class AprSubmissionSnapshotMemory : ICpuMemory, ICpuMemoryWrapper
    {
        private readonly ICpuMemory _inner;
        private readonly ulong _buffer;
        private readonly byte[] _records;

        public AprSubmissionSnapshotMemory(
            ICpuMemory inner,
            ulong buffer,
            byte[] records)
        {
            _inner = inner;
            _buffer = buffer;
            _records = records;
        }

        public ICpuMemory Inner => _inner;

        public bool TryRead(ulong virtualAddress, Span<byte> destination)
        {
            if (virtualAddress >= _buffer)
            {
                var relative = virtualAddress - _buffer;
                if (relative <= (ulong)_records.Length &&
                    (ulong)destination.Length <= (ulong)_records.Length - relative)
                {
                    _records.AsSpan(checked((int)relative), destination.Length)
                        .CopyTo(destination);
                    return true;
                }
            }

            return _inner.TryRead(virtualAddress, destination);
        }

        public bool TryWrite(ulong virtualAddress, ReadOnlySpan<byte> source) =>
            _inner.TryWrite(virtualAddress, source);

        public bool TryCompare(ulong virtualAddress, ReadOnlySpan<byte> expected) =>
            _inner.TryCompare(virtualAddress, expected);

        public bool TryCopy(ulong destinationAddress, ulong sourceAddress, ulong length) =>
            _inner.TryCopy(destinationAddress, sourceAddress, length);

        public bool TryWriteCapturedRecord(
            ulong virtualAddress,
            ReadOnlySpan<byte> source)
        {
            if (virtualAddress < _buffer)
            {
                return false;
            }

            var relative = virtualAddress - _buffer;
            if (relative > (ulong)_records.Length ||
                (ulong)source.Length > (ulong)_records.Length - relative)
            {
                return false;
            }

            source.CopyTo(_records.AsSpan(checked((int)relative), source.Length));
            return true;
        }
    }

    internal static AprIoPerfSnapshot GetAprIoPerfSnapshotV1825() =>
        new(
            Interlocked.Read(ref _v73016CompletedReadTraceCount),
            Interlocked.Read(ref _v1825IoBytes),
            Interlocked.Read(ref _v1825HostReadTicks),
            Interlocked.Read(ref _v1825GuestWriteTicks));

    internal static int TryCaptureCommandBufferSubmission(
        CpuContext ctx,
        ulong commandBuffer,
        out AprCommandBufferSubmissionSnapshot? snapshot)
    {
        snapshot = null;
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryGetCommandBufferState(
                ctx,
                commandBuffer,
                out _,
                out _,
                out var state) ||
            state is null)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        ulong buffer;
        ulong size;
        ulong writeOffset;
        lock (state)
        {
            buffer = state.Buffer;
            size = state.Size;
            writeOffset = state.WriteOffset;
        }

        if (buffer == 0 ||
            writeOffset > size ||
            writeOffset > int.MaxValue)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        var records = writeOffset == 0
            ? Array.Empty<byte>()
            : GC.AllocateUninitializedArray<byte>(checked((int)writeOffset));
        if (records.Length != 0 &&
            !ctx.Memory.TryRead(buffer, records))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        snapshot = new AprCommandBufferSubmissionSnapshot(
            commandBuffer,
            buffer,
            writeOffset,
            records);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    // SHARPEMU_V74_0_95_1_APR_PARALLEL_CLASSIFIER
    // Only a single explicit-offset ReadFile command (plus per-submission
    // completion records) may run concurrently. Sequential-offset reads and
    // AMM/unknown commands remain ordered barriers in KernelAprCompatExports.
    internal static bool IsParallelIoSafeV740951(
        AprCommandBufferSubmissionSnapshot snapshot)
    {
        if (snapshot.WriteOffset == 0 ||
            snapshot.WriteOffset > (ulong)snapshot.Records.Length)
        {
            return false;
        }

        var records = snapshot.Records.AsSpan();
        var offset = 0UL;
        var readCount = 0;

        while (offset < snapshot.WriteOffset)
        {
            if (offset > int.MaxValue ||
                snapshot.WriteOffset - offset < sizeof(uint))
            {
                return false;
            }

            var index = checked((int)offset);
            var recordType = BinaryPrimitives.ReadUInt32LittleEndian(
                records[index..]);

            switch (recordType)
            {
                case ReadFileRecordType:
                {
                    if (snapshot.WriteOffset - offset < ReadFileRecordSize)
                    {
                        return false;
                    }

                    var fileOffset = BinaryPrimitives.ReadUInt64LittleEndian(
                        records[(index + 0x18)..]);
                    if (fileOffset == ulong.MaxValue ||
                        fileOffset > long.MaxValue)
                    {
                        return false;
                    }

                    readCount++;
                    if (readCount != 1)
                    {
                        return false;
                    }

                    offset += ReadFileRecordSize;
                    break;
                }

                case KernelEventQueueRecordType:
                    if (snapshot.WriteOffset - offset < KernelEventQueueRecordSize)
                    {
                        return false;
                    }
                    offset += KernelEventQueueRecordSize;
                    break;

                case WriteAddressRecordType:
                    if (snapshot.WriteOffset - offset < WriteAddressRecordSize)
                    {
                        return false;
                    }
                    offset += WriteAddressRecordSize;
                    break;

                default:
                    // AMM and unknown records are ordering-sensitive barriers.
                    return false;
            }
        }

        return readCount == 1 && offset == snapshot.WriteOffset;
    }

    private sealed class CommandBufferState
    {
        public ulong Buffer;
        public ulong Size;
        public ulong WriteOffset;
        public ulong CommandCount;
    }

    private sealed class CachedHostFile : IDisposable
    {
        public CachedHostFile(string path)
        {
            Handle = File.OpenHandle(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                FileOptions.RandomAccess);
            Length = RandomAccess.GetLength(Handle);
        }

        public SafeFileHandle Handle { get; }
        public long Length { get; }

        // SHARPEMU_V74_0_95_1_APR_HOST_FILE_LEASE
        // Multi-worker APR must not let the LRU dispose a SafeFileHandle while
        // another worker is in RandomAccess.Read. Acquires/releases happen
        // under the cache gate plus an interlocked decrement on release.
        public int ActiveReaders;

        public void Dispose() => Handle.Dispose();
    }

    private sealed class CachedHostFileEntry
    {
        public required string Path { get; init; }
        public required CachedHostFile File { get; init; }
    }

    // Keep a bounded LRU of open host files. An unbounded cache exhausts the
    // process FD limit (~10k on macOS) during large asset storms, after
    // which every new open throws IOException and surfaces as NOT_FOUND — the
    // guest then reports InvalidFileFourCC on empty buffers.
    private const int MaxCachedHostFiles = 1536;
    private static readonly object _hostFileCacheGate = new();
    private static readonly Dictionary<string, LinkedListNode<CachedHostFileEntry>> _hostFileByPath =
        new(HostFsPath.Comparer);
    private static readonly LinkedList<CachedHostFileEntry> _hostFileLru = new();

    [SysAbiExport(
        Nid = "8aI7R7WaOlc",
        ExportName = "sceAmprCommandBufferConstructor",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferConstructor(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var buffer = ctx[CpuRegister.Rsi];
        var size = ctx[CpuRegister.Rdx];

        if (commandBuffer == 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        if (!InitializeCommandBuffer(ctx, commandBuffer, buffer, size, aux0: 0, aux1: 0, clear: true))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "ctor", commandBuffer, buffer, size);
        TryPreindexApp0();
        ctx[CpuRegister.Rax] = commandBuffer;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "a8uLzYY--tM",
        ExportName = "sceAmprAprCommandBufferConstructor",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AprCommandBufferConstructor(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var aux0 = ctx[CpuRegister.Rsi];
        var aux1 = ctx[CpuRegister.Rdx];

        if (commandBuffer == 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        if (!InitializeCommandBuffer(ctx, commandBuffer, buffer: 0, size: 0, aux0, aux1, clear: false))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "apr_ctor", commandBuffer, aux0, aux1);
        TryPreindexApp0();
        ctx[CpuRegister.Rax] = commandBuffer;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "Qs1xtplKo0U",
        ExportName = "sceAmprAprCommandBufferDestructor",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AprCommandBufferDestructor(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        Span<byte> auxiliaryPointers = stackalloc byte[sizeof(ulong) * 2];
        auxiliaryPointers.Clear();
        if (!ctx.Memory.TryWrite(commandBuffer + CommandBufferAux0Offset, auxiliaryPointers))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "apr_dtor", commandBuffer, 0, 0);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "GuchCTefuZw",
        ExportName = "sceAmprCommandBufferDestructor",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferDestructor(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        if (!WriteVisibleCommandBufferPointers(ctx, commandBuffer, buffer: 0, size: 0))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        _commandBuffers.TryRemove(commandBuffer, out _);
        TraceAmpr(ctx, "dtor", commandBuffer, 0, 0);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "N-FSPA4S3nI",
        ExportName = "sceAmprCommandBufferSetBuffer",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferSetBuffer(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var buffer = ctx[CpuRegister.Rsi];
        var size = ctx[CpuRegister.Rdx];

        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!WriteCommandBufferPointers(ctx, commandBuffer, buffer, size))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "set_buffer", commandBuffer, buffer, size);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "baQO9ez2gL4",
        ExportName = "sceAmprCommandBufferReset",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferReset(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        Span<byte> bufferPointers = stackalloc byte[sizeof(ulong) * 2];
        if (!ctx.Memory.TryRead(commandBuffer + CommandBufferDataOffset, bufferPointers))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        var buffer = BinaryPrimitives.ReadUInt64LittleEndian(bufferPointers);
        var size = BinaryPrimitives.ReadUInt64LittleEndian(bufferPointers[sizeof(ulong)..]);
        if (
            !WriteCommandBufferPointers(ctx, commandBuffer, buffer, size, writeOffset: 0))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "reset", commandBuffer, buffer, size);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "ULvXMDz56po",
        ExportName = "sceAmprCommandBufferClearBuffer",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferClearBuffer(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryGetCommandBufferState(ctx, commandBuffer, out var buffer, out var size, out _) ||
            !WriteVisibleCommandBufferPointers(ctx, commandBuffer, buffer: 0, size: 0))
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        _commandBuffers.TryRemove(commandBuffer, out _);
        TraceAmpr(ctx, "clear_buffer", commandBuffer, buffer, size);
        ctx[CpuRegister.Rax] = buffer;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "mQ16-QdKv7k",
        ExportName = "sceAmprAprCommandBufferReadFile",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AprCommandBufferReadFile(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var fileId = unchecked((uint)ctx[CpuRegister.Rcx]);
        var destination = ctx[CpuRegister.R8];
        var size = ctx[CpuRegister.R9];

        if (commandBuffer == 0 || (destination == 0 && size != 0))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!ctx.TryReadUInt64(ctx[CpuRegister.Rsp] + sizeof(ulong), out var fileOffset))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        // SHARPEMU_DEMONSSOULS_EBOOT_APR_DEFERRED_READ_V73_0_16
        // The PPSA01341 eboot builds this command without consuming its return
        // value, appends writeAddressOnCompletion, and checks the later
        // sceKernelAprSubmitCommandBuffer result. Match that ABI contract: this
        // export encodes the read only. Host I/O happens in command-buffer order
        // from CompleteCommandBuffer at submit time, before completion writes.
        if (!AppendReadFileRecord(
                ctx,
                commandBuffer,
                fileId,
                destination,
                size,
                fileOffset,
                bytesRead: 0))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceV73016Read(
            ref _v73016QueuedReadTraceCount,
            "APR_READ_QUEUED",
            commandBuffer,
            fileId,
            destination,
            size,
            fileOffset,
            bytesRead: 0,
            result: (int)OrbisGen2Result.ORBIS_GEN2_OK,
            hostPath: null);

        TraceAmprRead(
            ctx,
            commandBuffer,
            fileId,
            destination,
            size,
            fileOffset,
            bytesRead: 0,
            hostPath: null,
            result: (int)OrbisGen2Result.ORBIS_GEN2_OK);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "vWU-odnS+fU",
        ExportName = "sceAmprMeasureCommandSizeReadFile",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int MeasureCommandSizeReadFile(CpuContext ctx)
    {
        TraceAmpr(ctx, "measure_read_file", 0, ReadFileRecordSize, 0);
        ctx[CpuRegister.Rax] = ReadFileRecordSize;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "sSAUCCU1dv4",
        ExportName = "sceAmprMeasureCommandSizeWriteKernelEventQueue_04_00",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int MeasureCommandSizeWriteKernelEventQueue0400(CpuContext ctx)
    {
        TraceAmpr(ctx, "measure_write_equeue", 0, KernelEventQueueRecordSize, 0);
        ctx[CpuRegister.Rax] = KernelEventQueueRecordSize;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "Zi3dBUjgyXI",
        ExportName = "sceAmprMeasureCommandSizeWriteKernelEventQueueOnCompletion",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int MeasureCommandSizeWriteKernelEventQueueOnCompletion(CpuContext ctx)
    {
        TraceAmpr(ctx, "measure_write_equeue_complete", 0, KernelEventQueueRecordSize, 0);
        ctx[CpuRegister.Rax] = KernelEventQueueRecordSize;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "C+IEj+BsAFM",
        ExportName = "sceAmprMeasureCommandSizeWriteAddressOnCompletion",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int MeasureCommandSizeWriteAddressOnCompletion(CpuContext ctx)
    {
        TraceAmpr(ctx, "measure_write_address_complete", 0, WriteAddressRecordSize, 0);
        ctx[CpuRegister.Rax] = WriteAddressRecordSize;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "4fgtGfXDrFc",
        ExportName = "sceAmprMeasureCommandSizeWriteAddress_04_00",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int MeasureCommandSizeWriteAddress0400(CpuContext ctx)
    {
        TraceAmpr(ctx, "measure_write_address", 0, WriteAddressRecordSize, 0);
        ctx[CpuRegister.Rax] = WriteAddressRecordSize;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    // ---------------------------------------------------------------------
    // AMM command-buffer family (Gen5)
    //
    // The PS5 AMPR/AMM queue owns an address-map command stream.  SharpEmu
    // uses a unified guest-memory model rather than a second hardware AMM
    // aperture, so these commands must still be represented in the command
    // buffer and completed in-order even when no separate host remap is
    // required.  Returning NOT_FOUND here aborts Unreal/REDEngine-style
    // platform-memory startup before the renderer is created.
    // ---------------------------------------------------------------------

    [SysAbiExport(
        Nid = "6hbai6KIXkk",
        ExportName = "sceAmprAmmMeasureAmmCommandSizeMap",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmMeasureCommandSizeMap(CpuContext ctx) =>
        MeasureAmmCommand(ctx, AmmOpcodeMap, "amm_measure_map");

    [SysAbiExport(
        Nid = "ZFDZoN9IbVU",
        ExportName = "sceAmprAmmMeasureAmmCommandSizeMapDirect",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmMeasureCommandSizeMapDirect(CpuContext ctx) =>
        MeasureAmmCommand(ctx, AmmOpcodeMapDirect, "amm_measure_map_direct");

    [SysAbiExport(
        Nid = "4SSJ+cn+Pvg",
        ExportName = "sceAmprAmmMeasureAmmCommandSizeMapAsPrt",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmMeasureCommandSizeMapAsPrt(CpuContext ctx) =>
        MeasureAmmCommand(ctx, AmmOpcodeMapAsPrt, "amm_measure_map_prt");

    [SysAbiExport(
        Nid = "8sFq5s8eHnQ",
        ExportName = "sceAmprAmmMeasureAmmCommandSizeRemap",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmMeasureCommandSizeRemap(CpuContext ctx) =>
        MeasureAmmCommand(ctx, AmmOpcodeRemap, "amm_measure_remap");

    [SysAbiExport(
        Nid = "dSS7bQGCfco",
        ExportName = "sceAmprAmmMeasureAmmCommandSizeRemapIntoPrt",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmMeasureCommandSizeRemapIntoPrt(CpuContext ctx) =>
        MeasureAmmCommand(ctx, AmmOpcodeRemapIntoPrt, "amm_measure_remap_prt");

    [SysAbiExport(
        Nid = "Ayg6PIon2wA",
        ExportName = "sceAmprAmmMeasureAmmCommandSizeUnmap",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmMeasureCommandSizeUnmap(CpuContext ctx) =>
        MeasureAmmCommand(ctx, AmmOpcodeUnmap, "amm_measure_unmap");

    [SysAbiExport(
        Nid = "i4rGaIDpsW4",
        ExportName = "sceAmprAmmMeasureAmmCommandSizeUnmapToPrt",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmMeasureCommandSizeUnmapToPrt(CpuContext ctx) =>
        MeasureAmmCommand(ctx, AmmOpcodeUnmapToPrt, "amm_measure_unmap_prt");

    [SysAbiExport(
        Nid = "JEVYGhDc97M",
        ExportName = "sceAmprAmmCommandBufferMap",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferMap(CpuContext ctx) =>
        AppendAmmCommand(ctx, AmmOpcodeMap, "amm_map");

    [SysAbiExport(
        Nid = "8TBE+9XCZbI",
        ExportName = "sceAmprAmmCommandBufferMapDirect",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferMapDirect(CpuContext ctx) =>
        AppendAmmCommand(ctx, AmmOpcodeMapDirect, "amm_map_direct");

    [SysAbiExport(
        Nid = "ZJCgt+aPHAU",
        ExportName = "sceAmprAmmCommandBufferMapAsPrt",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferMapAsPrt(CpuContext ctx) =>
        AppendAmmCommand(ctx, AmmOpcodeMapAsPrt, "amm_map_prt");

    [SysAbiExport(
        Nid = "ijvRMHfwwjc",
        ExportName = "sceAmprAmmCommandBufferRemap",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferRemap(CpuContext ctx) =>
        AppendAmmCommand(ctx, AmmOpcodeRemap, "amm_remap");

    [SysAbiExport(
        Nid = "0Xo9g4goDXU",
        ExportName = "sceAmprAmmCommandBufferRemapIntoPrt",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferRemapIntoPrt(CpuContext ctx) =>
        AppendAmmCommand(ctx, AmmOpcodeRemapIntoPrt, "amm_remap_prt");

    [SysAbiExport(
        Nid = "M-VFI2DJWQA",
        ExportName = "sceAmprAmmCommandBufferUnmap",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferUnmap(CpuContext ctx) =>
        AppendAmmCommand(ctx, AmmOpcodeUnmap, "amm_unmap");

    [SysAbiExport(
        Nid = "3A2X6OCHtnA",
        ExportName = "sceAmprAmmCommandBufferUnmapToPrt",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferUnmapToPrt(CpuContext ctx) =>
        AppendAmmCommand(ctx, AmmOpcodeUnmapToPrt, "amm_unmap_prt");

    // ---------------------------------------------------------------------
    // V63 — AMM command-buffer lifecycle + submission
    //
    // Evidence from PPSA09790 after V62:
    //   RPCAhx-aabE = sceAmprCommandBufferGetBufferBaseAddress
    //   lwS-7y3jcBI = sceAmprAmmSubmitCommandBuffer
    // The game calls GetBufferBaseAddress(commandBuffer) and passes the
    // returned base directly to SubmitCommandBuffer.  V63 keeps submission
    // synchronous in SharpEmu's unified guest-memory model and completes the
    // V62 AMM records in-order before returning success.
    // ---------------------------------------------------------------------

    [SysAbiExport(
        Nid = "EDq5bqCqYpA",
        ExportName = "sceAmprAmmCommandBufferConstructor",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferConstructor(CpuContext ctx)
    {

        var commandBuffer = ctx[CpuRegister.Rdi];
        var buffer = ctx[CpuRegister.Rsi];
        var size = ctx[CpuRegister.Rdx];
        var aux0 = ctx[CpuRegister.Rcx];
        var aux1 = ctx[CpuRegister.R8];

        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!InitializeCommandBuffer(ctx, commandBuffer, buffer, size, aux0, aux1, clear: true))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "amm_ctor", commandBuffer, buffer, size);
        ctx[CpuRegister.Rax] = commandBuffer;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "pvUFDOHilnE",
        ExportName = "sceAmprAmmCommandBufferDestructor",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmCommandBufferDestructor(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        _commandBuffers.TryRemove(commandBuffer, out _);
        if (!WriteVisibleCommandBufferPointers(ctx, commandBuffer, buffer: 0, size: 0))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "amm_dtor", commandBuffer, 0, 0);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "RPCAhx-aabE",
        ExportName = "sceAmprCommandBufferGetBufferBaseAddress",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferGetBufferBaseAddress(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryGetCommandBufferState(ctx, commandBuffer, out var buffer, out _, out _))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "get_buffer_base", commandBuffer, buffer, 0);
        ctx[CpuRegister.Rax] = buffer;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "Q07J7XpvhrU",
        ExportName = "sceAmprAmmGiveDirectMemory",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmGiveDirectMemory(CpuContext ctx)
    {
        // The observed Gen5 ABI is identical to sceKernelAllocateDirectMemory.
        // Use the kernel allocator as the single authority for direct-memory
        // accounting instead of maintaining a second AMPR-only allocator.
        return KernelMemoryCompatExports.KernelAllocateDirectMemory(ctx);
    }

    [SysAbiExport(
        Nid = "lwS-7y3jcBI",
        ExportName = "sceAmprAmmSubmitCommandBuffer",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmSubmitCommandBuffer(CpuContext ctx) =>
        SubmitAmmCommandBuffer(ctx, "amm_submit");

    [SysAbiExport(
        Nid = "OJf3vCckPAM",
        ExportName = "sceAmprAmmSubmitCommandBuffer2",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmSubmitCommandBuffer2(CpuContext ctx) =>
        SubmitAmmCommandBuffer(ctx, "amm_submit2");

    [SysAbiExport(
        Nid = "NnKhlMJtIsI",
        ExportName = "sceAmprAmmSubmitCommandBuffer3",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmSubmitCommandBuffer3(CpuContext ctx) =>
        SubmitAmmCommandBuffer(ctx, "amm_submit3");

    [SysAbiExport(
        Nid = "HXymib4T8gc",
        ExportName = "sceAmprAmmWaitCommandBufferCompletion",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int AmmWaitCommandBufferCompletion(CpuContext ctx)
    {
        // Submissions are completed synchronously by SubmitAmmCommandBuffer.
        // Preserve the API contract: a successfully submitted buffer is
        // already visible to CPU/GPU consumers when wait returns.
        TraceAmpr(ctx, "amm_wait_complete", ctx[CpuRegister.Rdi], ctx[CpuRegister.Rsi], ctx[CpuRegister.Rdx]);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "tZDDEo2tE5k",
        ExportName = "sceAmprCommandBufferGetSize",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferGetSize(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryGetCommandBufferState(ctx, commandBuffer, out _, out var size, out _))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "get_size", commandBuffer, size, 0);
        ctx[CpuRegister.Rax] = size;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "GnxKOHEawhk",
        ExportName = "sceAmprCommandBufferGetCurrentOffset",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferGetCurrentOffset(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryGetCommandBufferOffset(ctx, commandBuffer, out var offset))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "get_offset", commandBuffer, offset, 0);
        ctx[CpuRegister.Rax] = offset;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "gzndltBEzWc",
        ExportName = "sceAmprCommandBufferGetNumCommands",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferGetNumCommands(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryGetCommandBufferState(ctx, commandBuffer, out _, out _, out var state) || state is null)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        ulong commandCount;
        lock (state)
        {
            commandCount = state.CommandCount;
        }

        TraceAmpr(ctx, "get_num_commands", commandBuffer, commandCount, 0);
        ctx[CpuRegister.Rax] = commandCount;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "H896Pt-yB4I",
        ExportName = "sceAmprCommandBufferWriteKernelEventQueue_04_00",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferWriteKernelEventQueue0400(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var equeue = ctx[CpuRegister.Rsi];
        var ident = ctx[CpuRegister.Rdx];
        var completionToken = ctx[CpuRegister.Rcx];
        var userData = ctx[CpuRegister.R8];

        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!AppendKernelEventQueueRecord(
                ctx,
                commandBuffer,
                equeue,
                ident,
                completionToken,
                userData))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "write_equeue", commandBuffer, ident, completionToken);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "o67gODLFpls",
        ExportName = "sceAmprCommandBufferWriteKernelEventQueueOnCompletion",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferWriteKernelEventQueueOnCompletion(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var equeue = ctx[CpuRegister.Rsi];
        var ident = ctx[CpuRegister.Rdx];
        var completionToken = ctx[CpuRegister.Rcx];
        var userData = ctx[CpuRegister.R8];

        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!AppendKernelEventQueueRecord(
                ctx,
                commandBuffer,
                equeue,
                ident,
                completionToken,
                userData))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "write_equeue_complete", commandBuffer, ident, completionToken);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "sJXyWHjP-F8",
        ExportName = "sceAmprCommandBufferWriteAddressOnCompletion",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferWriteAddressOnCompletion(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var address = ctx[CpuRegister.Rsi];
        var value = ctx[CpuRegister.Rdx];

        if (commandBuffer == 0 || address == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!AppendWriteAddressRecord(ctx, commandBuffer, address, value))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "write_address_complete", commandBuffer, address, value);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "j0+3uJMxYJY",
        ExportName = "sceAmprCommandBufferWriteAddress_04_00",
        Target = Generation.Gen5,
        LibraryName = "libSceAmpr")]
    public static int CommandBufferWriteAddress0400(CpuContext ctx)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        var address = ctx[CpuRegister.Rsi];
        var value = ctx[CpuRegister.Rdx];

        if (commandBuffer == 0 || address == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!AppendWriteAddressRecord(ctx, commandBuffer, address, value))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(ctx, "write_address", commandBuffer, address, value);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    public static int CompleteCommandBuffer(CpuContext ctx, ulong commandBuffer)
    {
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryGetCommandBufferState(
                ctx,
                commandBuffer,
                out var buffer,
                out _,
                out var state) ||
            state is null)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        ulong writeOffset;
        lock (state)
        {
            writeOffset = state.WriteOffset;
        }

        return CompleteCommandBufferRange(
            ctx,
            commandBuffer,
            buffer,
            writeOffset);
    }

    // V1.8.25 snapshots the command records synchronously at submit time, then
    // performs host file I/O on the APR worker. The guest may reuse/reset its
    // command buffer after submission without changing the worker's record walk.
    internal static int CompleteCommandBuffer(
        CpuContext ctx,
        AprCommandBufferSubmissionSnapshot snapshot)
    {
        var snapshotMemory = new AprSubmissionSnapshotMemory(
            ctx.Memory,
            snapshot.Buffer,
            snapshot.Records);
        var snapshotContext = new CpuContext(
            snapshotMemory,
            ctx.TargetGeneration);

        return CompleteCommandBufferRange(
            snapshotContext,
            snapshot.CommandBuffer,
            snapshot.Buffer,
            snapshot.WriteOffset);
    }

    private static int CompleteCommandBufferRange(
        CpuContext ctx,
        ulong commandBuffer,
        ulong buffer,
        ulong writeOffset)
    {
        var offset = 0UL;
        while (offset < writeOffset)
        {
            if (!TryReadUInt32(ctx, buffer + offset, out var recordType))
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }

            switch (recordType)
            {
                case ReadFileRecordType:
                {
                    var readResult = CompleteReadFileRecord(
                        ctx,
                        commandBuffer,
                        buffer + offset);
                    if (readResult != (int)OrbisGen2Result.ORBIS_GEN2_OK)
                    {
                        return readResult;
                    }

                    offset += ReadFileRecordSize;
                    break;
                }

                case KernelEventQueueRecordType:
                    if (!CompleteKernelEventQueueRecord(ctx, buffer + offset))
                    {
                        return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                    }

                    offset += KernelEventQueueRecordSize;
                    break;

                case WriteAddressRecordType:
                    if (!CompleteWriteAddressRecord(ctx, buffer + offset))
                    {
                        return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                    }

                    offset += WriteAddressRecordSize;
                    break;

                case AmmRecordType:
                    if (!CompleteAmmRecord(ctx, buffer + offset))
                    {
                        return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
                    }

                    offset += AmmRecordSize;
                    break;

                default:
                    TraceAmpr(
                        ctx,
                        "complete_unknown",
                        commandBuffer,
                        recordType,
                        offset);
                    return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
            }
        }

        TraceAmpr(ctx, "complete", commandBuffer, buffer, writeOffset);
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int SubmitAmmCommandBuffer(CpuContext ctx, string traceName)
    {
        var bufferBase = ctx[CpuRegister.Rdi];
        var submittedSize = ctx[CpuRegister.Rsi];

        if (bufferBase == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (!TryResolveCommandBufferByBufferBase(bufferBase, out var commandBuffer, out var state) ||
            state is null)
        {
            TraceAmpr(ctx, traceName + "_untracked", bufferBase, submittedSize, 0);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        ulong allocatedSize;
        ulong writeOffset;
        lock (state)
        {
            allocatedSize = state.Size;
            writeOffset = state.WriteOffset;
        }

        // A submit may include transport/header bytes in its visible size,
        // therefore only reject values that are clearly outside the tracked
        // backing allocation.  The actual record walk is bounded by WriteOffset.
        if (allocatedSize != 0 && submittedSize > allocatedSize)
        {
            TraceAmpr(ctx, traceName + "_oversize", bufferBase, submittedSize, allocatedSize);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        var result = CompleteCommandBuffer(ctx, commandBuffer);
        TraceAmpr(ctx, traceName, bufferBase, submittedSize, writeOffset);

        if (result == (int)OrbisGen2Result.ORBIS_GEN2_OK)
        {
            ctx[CpuRegister.Rax] = 0;
        }

        return result;
    }

    private static bool TryResolveCommandBufferByBufferBase(
        ulong bufferBase,
        out ulong commandBuffer,
        out CommandBufferState? state)
    {
        foreach (var pair in _commandBuffers)
        {
            var candidate = pair.Value;
            lock (candidate)
            {
                if (candidate.Buffer != bufferBase)
                {
                    continue;
                }
            }

            commandBuffer = pair.Key;
            state = candidate;
            return true;
        }

        commandBuffer = 0;
        state = null;
        return false;
    }

    private static bool InitializeCommandBuffer(
        CpuContext ctx,
        ulong commandBuffer,
        ulong buffer,
        ulong size,
        ulong aux0,
        ulong aux1,
        bool clear)
    {
        Span<byte> header = stackalloc byte[CommandBufferHeaderSize];
        if (clear)
        {
            header.Clear();
        }
        else
        {
            if (!ctx.Memory.TryRead(commandBuffer, header))
            {
                return false;
            }

            buffer = BinaryPrimitives.ReadUInt64LittleEndian(header[(int)CommandBufferDataOffset..]);
            size = BinaryPrimitives.ReadUInt64LittleEndian(header[(int)CommandBufferSizeOffset..]);
        }

        BinaryPrimitives.WriteUInt64LittleEndian(header[(int)CommandBufferSelfOffset..], commandBuffer);
        BinaryPrimitives.WriteUInt64LittleEndian(header[(int)CommandBufferDataOffset..], buffer);
        BinaryPrimitives.WriteUInt64LittleEndian(header[(int)CommandBufferSizeOffset..], size);
        BinaryPrimitives.WriteUInt64LittleEndian(header[(int)CommandBufferAux0Offset..], aux0);
        BinaryPrimitives.WriteUInt64LittleEndian(header[(int)CommandBufferAux1Offset..], aux1);
        if (!ctx.Memory.TryWrite(commandBuffer, header))
        {
            return false;
        }

        UpdateCommandBufferState(commandBuffer, buffer, size, writeOffset: 0);
        return true;
    }

    private static bool WriteCommandBufferPointers(CpuContext ctx, ulong commandBuffer, ulong buffer, ulong size)
    {
        return WriteCommandBufferPointers(ctx, commandBuffer, buffer, size, writeOffset: 0);
    }

    private static bool WriteCommandBufferPointers(CpuContext ctx, ulong commandBuffer, ulong buffer, ulong size, ulong writeOffset)
    {
        if (!WriteVisibleCommandBufferPointers(ctx, commandBuffer, buffer, size))
        {
            return false;
        }

        UpdateCommandBufferState(commandBuffer, buffer, size, writeOffset);

        return true;
    }

    private static bool WriteVisibleCommandBufferPointers(CpuContext ctx, ulong commandBuffer, ulong buffer, ulong size)
    {
        Span<byte> pointers = stackalloc byte[sizeof(ulong) * 3];
        BinaryPrimitives.WriteUInt64LittleEndian(pointers, commandBuffer);
        BinaryPrimitives.WriteUInt64LittleEndian(pointers[sizeof(ulong)..], buffer);
        BinaryPrimitives.WriteUInt64LittleEndian(pointers[(sizeof(ulong) * 2)..], size);
        return ctx.Memory.TryWrite(commandBuffer + CommandBufferSelfOffset, pointers);
    }

    private static void UpdateCommandBufferState(
        ulong commandBuffer,
        ulong buffer,
        ulong size,
        ulong writeOffset)
    {
        var state = _commandBuffers.GetOrAdd(commandBuffer, static _ => new CommandBufferState());
        lock (state)
        {
            state.Buffer = buffer;
            state.Size = size;
            state.WriteOffset = writeOffset;
            state.CommandCount = 0;
        }
    }

    private static bool TryGetCommandBufferState(
        CpuContext ctx,
        ulong commandBuffer,
        out ulong buffer,
        out ulong size,
        out CommandBufferState? state)
    {
        if (_commandBuffers.TryGetValue(commandBuffer, out state))
        {
            lock (state)
            {
                buffer = state.Buffer;
                size = state.Size;
            }

            return true;
        }

        Span<byte> pointers = stackalloc byte[sizeof(ulong) * 2];
        if (ctx.Memory.TryRead(commandBuffer + CommandBufferDataOffset, pointers))
        {
            buffer = BinaryPrimitives.ReadUInt64LittleEndian(pointers);
            size = BinaryPrimitives.ReadUInt64LittleEndian(pointers[sizeof(ulong)..]);
            state = _commandBuffers.GetOrAdd(commandBuffer, static _ => new CommandBufferState());
            lock (state)
            {
                state.Buffer = buffer;
                state.Size = size;
                state.WriteOffset = 0;
                state.CommandCount = 0;
            }

            return true;
        }

        buffer = 0;
        size = 0;
        state = null;
        return false;
    }

    private static bool TryGetCommandBufferOffset(CpuContext ctx, ulong commandBuffer, out ulong offset)
    {
        if (!TryGetCommandBufferState(ctx, commandBuffer, out _, out _, out var state) || state is null)
        {
            offset = 0;
            return false;
        }

        lock (state)
        {
            offset = state.WriteOffset;
        }

        return true;
    }

    // SHARPEMU_APR_PAK_SMALL_READ_READAHEAD_V1_8_32
    // DBFZ performs thousands of tiny random reads from pakchunk*.pak. The
    // underlying host reads are already fast; the remaining avoidable work is
    // one host syscall + ArrayPool round-trip + path/handle lookup per tiny
    // request. Keep an 8-page, 64 KiB ThreadStatic read-ahead cache for .pak
    // files only. Large reads remain on the V1.8.25 4 MiB direct path.
    private const int PakReadPageSizeV1832 = 64 * 1024;
    private const int PakReadPageSlotsV1832 = 8;
    private const ulong PakSmallReadThresholdV1832 = 64 * 1024;

    private sealed class PakReadPageV1832
    {
        public string? HostPath;
        public long PageOffset = -1;
        public int ValidLength;
        public byte[]? Data;
    }

    [ThreadStatic]
    private static PakReadPageV1832[]? _pakReadPagesV1832;
    [ThreadStatic]
    private static int _pakReadReplacementV1832;
    [ThreadStatic]
    private static uint _lastAprFileIdV1832;
    [ThreadStatic]
    private static string? _lastAprHostPathV1832;
    [ThreadStatic]
    private static bool _lastAprFileValidV1832;
    [ThreadStatic]
    private static byte[]? _smallDirectReadBufferV740103;

    private static long _pakSmallReadRequestsV1832;
    private static long _pakPageHitsV1832;
    private static long _pakPageMissesV1832;
    private static long _pakPageHostReadBytesV1832;
    private static long _pakPageHostReadSyscallsV1832;
    private static long _directHostReadSyscallsV1832;
    private static long _v740103HostOpenTicks;
    private static long _v740103HostOpenCount;
    private static long _v740103SmallBufferHits;

    private static bool IsPakReadAheadEnabledV1832() =>
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_APR_PAK_READAHEAD"),
            "0",
            StringComparison.OrdinalIgnoreCase);

    // SHARPEMU_V74_0_56_30_APR_ASSET_READAHEAD
    // V56.27.1 proved that Demon's Souls streams thousands of individual
    // CTXR/CTXC/CSDR/CGPR/CFON/CTXT/AT9 assets through APR. The existing 64 KiB
    // page cache was restricted to .pak, so every one of those requests went
    // through RandomAccess.Read even when the same small asset/stream page was
    // requested repeatedly.
    private static bool IsAssetReadAheadEnabledV7405630() =>
        string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_APR_ASSET_READAHEAD"),
            "1",
            StringComparison.OrdinalIgnoreCase);

    private static bool IsReadAheadAssetV7405630(string hostPath)
    {
        var extension = Path.GetExtension(hostPath);

        return extension.Equals(".ctxr", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".ctxc", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".cmat", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".cmsh", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".cmdl", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".csdr", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".cslt", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".cgpr", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".cfon", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".ctxt", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".cxml", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".drb", StringComparison.OrdinalIgnoreCase) ||
               extension.Equals(".at9", StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryResolveAprHostPathV1832(
        uint fileId,
        out string hostPath)
    {
        if (_lastAprFileValidV1832 &&
            _lastAprFileIdV1832 == fileId &&
            _lastAprHostPathV1832 is { } cached)
        {
            hostPath = cached;
            return true;
        }

        if (!AmprFileRegistry.TryGetHostPath(fileId, out hostPath!))
        {
            return false;
        }

        _lastAprFileIdV1832 = fileId;
        _lastAprHostPathV1832 = hostPath;
        _lastAprFileValidV1832 = true;
        return true;
    }

    private static PakReadPageV1832[] GetPakReadPagesV1832()
    {
        var pages = _pakReadPagesV1832;
        if (pages is not null)
        {
            return pages;
        }

        pages = new PakReadPageV1832[PakReadPageSlotsV1832];
        _pakReadPagesV1832 = pages;
        return pages;
    }

    private static bool TryGetPakReadPageV1832(
        string hostPath,
        long pageOffset,
        out PakReadPageV1832? page,
        out int result)
    {
        result = (int)OrbisGen2Result.ORBIS_GEN2_OK;
        var pages = GetPakReadPagesV1832();

        for (var index = 0; index < pages.Length; index++)
        {
            var candidate = pages[index];
            if (candidate is null ||
                candidate.PageOffset != pageOffset ||
                candidate.HostPath is null ||
                !HostFsPath.Comparer.Equals(candidate.HostPath, hostPath))
            {
                continue;
            }

            Interlocked.Increment(ref _pakPageHitsV1832);
            page = candidate;
            return true;
        }

        Interlocked.Increment(ref _pakPageMissesV1832);

        if (!TryGetCachedHostFile(
                hostPath,
                out var cachedFile,
                out result))
        {
            page = null;
            return false;
        }

        try
        {
            var slotIndex =
                unchecked(_pakReadReplacementV1832++) &
                (PakReadPageSlotsV1832 - 1);
            var slot = pages[slotIndex];
            if (slot is null)
            {
                slot = new PakReadPageV1832();
                pages[slotIndex] = slot;
            }

            slot.Data ??= new byte[PakReadPageSizeV1832];

            var readStarted = System.Diagnostics.Stopwatch.GetTimestamp();
            var read = RandomAccess.Read(
                cachedFile.Handle,
                slot.Data.AsSpan(0, PakReadPageSizeV1832),
                pageOffset);
            Interlocked.Add(
                ref _v1825HostReadTicks,
                System.Diagnostics.Stopwatch.GetTimestamp() - readStarted);
            Interlocked.Increment(ref _pakPageHostReadSyscallsV1832);

            if (read < 0)
            {
                page = null;
                result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
                return false;
            }

            slot.HostPath = hostPath;
            slot.PageOffset = pageOffset;
            slot.ValidLength = read;

            if (read > 0)
            {
                Interlocked.Add(ref _pakPageHostReadBytesV1832, read);
            }

            page = slot;
            return true;
        }
        finally
        {
            ReleaseCachedHostFileV740951(cachedFile);
        }
    }

    private static int TryReadSmallPakCachedV1832(
        CpuContext ctx,
        string hostPath,
        ulong fileOffset,
        ulong destination,
        ulong size,
        out ulong bytesRead)
    {
        bytesRead = 0;
        Interlocked.Increment(ref _pakSmallReadRequestsV1832);

        while (bytesRead < size)
        {
            var absoluteOffset = fileOffset + bytesRead;
            if (absoluteOffset > long.MaxValue)
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
            }

            var pageOffset =
                unchecked((long)absoluteOffset) &
                ~((long)PakReadPageSizeV1832 - 1L);
            var inPage =
                checked((int)(absoluteOffset - unchecked((ulong)pageOffset)));

            if (!TryGetPakReadPageV1832(
                    hostPath,
                    pageOffset,
                    out var page,
                    out var pageResult) ||
                page is null)
            {
                return pageResult;
            }

            if (inPage >= page.ValidLength)
            {
                break;
            }

            var available = page.ValidLength - inPage;
            var requested = checked((int)Math.Min(
                (ulong)available,
                size - bytesRead));
            if (requested <= 0)
            {
                break;
            }

            var writeStarted = System.Diagnostics.Stopwatch.GetTimestamp();
            var wrote = ctx.Memory.TryWrite(
                destination + bytesRead,
                page.Data!.AsSpan(inPage, requested));
            Interlocked.Add(
                ref _v1825GuestWriteTicks,
                System.Diagnostics.Stopwatch.GetTimestamp() - writeStarted);

            if (!wrote)
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }

            Interlocked.Add(ref _v1825IoBytes, requested);
            bytesRead += unchecked((ulong)requested);

            if (requested < available &&
                bytesRead >= size)
            {
                break;
            }
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static void TracePakReadCacheV1832()
    {
        var completed = Interlocked.Read(ref _v73016CompletedReadTraceCount);
        if (completed <= 0 ||
            (completed > 32 && (completed & (completed - 1)) != 0))
        {
            return;
        }

        var hits = Interlocked.Read(ref _pakPageHitsV1832);
        var misses = Interlocked.Read(ref _pakPageMissesV1832);
        var probes = hits + misses;
        var hitRate = probes == 0
            ? 0.0
            : hits * 100.0 / probes;

        Console.Error.WriteLine(
            $"[APR-CACHE-1832] completed={completed} " +
            $"small_requests={Interlocked.Read(ref _pakSmallReadRequestsV1832)} " +
            $"page_hits={hits} page_misses={misses} hit_rate={hitRate:F1} " +
            $"page_syscalls={Interlocked.Read(ref _pakPageHostReadSyscallsV1832)} " +
            $"direct_syscalls={Interlocked.Read(ref _directHostReadSyscallsV1832)} " +
            $"readahead_bytes={Interlocked.Read(ref _pakPageHostReadBytesV1832)} " +
            $"v103_open_count={Interlocked.Read(ref _v740103HostOpenCount)} " +
            $"v103_open_ms={Interlocked.Read(ref _v740103HostOpenTicks) * 1000.0 / System.Diagnostics.Stopwatch.Frequency:F3} " +
            $"v103_small_buffer_hits={Interlocked.Read(ref _v740103SmallBufferHits)}");
    }
    private static int TryReadFileToGuestMemory(
        CpuContext ctx,
        string hostPath,
        ulong fileOffset,
        ulong destination,
        ulong size,
        out ulong bytesRead)
    {
        bytesRead = 0;
        if (size == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        if (fileOffset > long.MaxValue)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        var pakSmallRead =
            IsPakReadAheadEnabledV1832() &&
            size <= PakSmallReadThresholdV1832 &&
            hostPath.EndsWith(".pak", StringComparison.OrdinalIgnoreCase);

        var assetSmallReadV7405630 =
            IsAssetReadAheadEnabledV7405630() &&
            size <= PakSmallReadThresholdV1832 &&
            IsReadAheadAssetV7405630(hostPath);

        try
        {
            if (pakSmallRead || assetSmallReadV7405630)
            {
                return TryReadSmallPakCachedV1832(
                    ctx,
                    hostPath,
                    fileOffset,
                    destination,
                    size,
                    out bytesRead);
            }

            // Keep the V1.8.25 direct path. V74.0.95.1 adds a lease so the
            // bounded host-file LRU cannot dispose this handle while another
            // APR worker performs positioned RandomAccess.Read calls.
            if (!TryGetCachedHostFile(
                    hostPath,
                    out var cachedFile,
                    out var openResult))
            {
                return openResult;
            }

            try
            {
                if (fileOffset >= (ulong)cachedFile.Length)
                {
                    return (int)OrbisGen2Result.ORBIS_GEN2_OK;
                }

                const int ChunkSize = 4 * 1024 * 1024;
                var useSmallBufferV740103 = size <= PakSmallReadThresholdV1832;
                byte[] buffer;
                if (useSmallBufferV740103)
                {
                    buffer = _smallDirectReadBufferV740103 ??=
                        GC.AllocateUninitializedArray<byte>(
                            checked((int)PakSmallReadThresholdV1832));
                    Interlocked.Increment(ref _v740103SmallBufferHits);
                }
                else
                {
                    buffer = ArrayPool<byte>.Shared.Rent(
                        (int)Math.Min((ulong)ChunkSize, size));
                }

                try
                {
                    while (bytesRead < size)
                    {
                        if (bytesRead > ulong.MaxValue - fileOffset)
                        {
                            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
                        }

                        var absoluteOffset = fileOffset + bytesRead;
                        if (absoluteOffset > long.MaxValue)
                        {
                            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
                        }

                        var request = (int)Math.Min(
                            (ulong)buffer.Length,
                            size - bytesRead);

                        var readStarted =
                            System.Diagnostics.Stopwatch.GetTimestamp();
                        var read = RandomAccess.Read(
                            cachedFile.Handle,
                            buffer.AsSpan(0, request),
                            unchecked((long)absoluteOffset));
                        Interlocked.Add(
                            ref _v1825HostReadTicks,
                            System.Diagnostics.Stopwatch.GetTimestamp() - readStarted);
                        Interlocked.Increment(ref _directHostReadSyscallsV1832);

                        if (read <= 0)
                        {
                            break;
                        }

                        var writeStarted =
                            System.Diagnostics.Stopwatch.GetTimestamp();
                        var wrote = ctx.Memory.TryWrite(
                            destination + bytesRead,
                            buffer.AsSpan(0, read));
                        Interlocked.Add(
                            ref _v1825GuestWriteTicks,
                            System.Diagnostics.Stopwatch.GetTimestamp() - writeStarted);

                        if (!wrote)
                        {
                            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                        }

                        Interlocked.Add(ref _v1825IoBytes, read);
                        bytesRead += unchecked((ulong)read);
                    }
                }
                finally
                {
                    if (!useSmallBufferV740103)
                    {
                        ArrayPool<byte>.Shared.Return(buffer);
                    }
                }
            }
            finally
            {
                ReleaseCachedHostFileV740951(cachedFile);
            }
        }
        catch (UnauthorizedAccessException)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_PERMISSION_DENIED;
        }
        catch (IOException)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
        }

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static bool TryGetCachedHostFile(
        string hostPath,
        out CachedHostFile file,
        out int result)
    {
        file = null!;
        result = (int)OrbisGen2Result.ORBIS_GEN2_OK;

        // V74.0.103: APR registry entries are already absolute host paths.
        // Avoid Path.GetFullPath and its string allocation on every one of the
        // thousands of startup reads; retain the defensive normalization only
        // for callers that supply a relative path.
        string cachePath;
        if (Path.IsPathFullyQualified(hostPath))
        {
            cachePath = hostPath;
        }
        else
        {
            try
            {
                cachePath = Path.GetFullPath(hostPath);
            }
            catch
            {
                cachePath = hostPath;
            }
        }

        lock (_hostFileCacheGate)
        {
            if (_hostFileByPath.TryGetValue(cachePath, out var existing))
            {
                _hostFileLru.Remove(existing);
                _hostFileLru.AddFirst(existing);
                file = existing.Value.File;
                Interlocked.Increment(ref file.ActiveReaders);
                return true;
            }
        }

        CachedHostFile opened;
        var openStartedV740103 = System.Diagnostics.Stopwatch.GetTimestamp();
        try
        {
            opened = new CachedHostFile(cachePath);
        }
        catch (UnauthorizedAccessException)
        {
            result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_PERMISSION_DENIED;
            return false;
        }
        catch (IOException)
        {
            // Evict only idle handles. Active APR readers are pinned until
            // their lease is released, preventing close-vs-read races.
            EvictAllCachedHostFilesV740951();
            try
            {
                opened = new CachedHostFile(cachePath);
            }
            catch (UnauthorizedAccessException)
            {
                result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_PERMISSION_DENIED;
                return false;
            }
            catch (IOException)
            {
                result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
                return false;
            }
        }
        finally
        {
            Interlocked.Add(
                ref _v740103HostOpenTicks,
                System.Diagnostics.Stopwatch.GetTimestamp() - openStartedV740103);
            Interlocked.Increment(ref _v740103HostOpenCount);
        }

        lock (_hostFileCacheGate)
        {
            if (_hostFileByPath.TryGetValue(cachePath, out var raced))
            {
                opened.Dispose();
                _hostFileLru.Remove(raced);
                _hostFileLru.AddFirst(raced);
                file = raced.Value.File;
                Interlocked.Increment(ref file.ActiveReaders);
                return true;
            }

            while (_hostFileByPath.Count >= MaxCachedHostFiles)
            {
                if (!EvictLeastRecentlyUsedHostFileLockedV740951())
                {
                    // At most the concurrently active APR workers should be
                    // pinned. Temporarily exceed the soft cache bound instead
                    // of disposing a handle that is being read.
                    break;
                }
            }

            var entry = new CachedHostFileEntry { Path = cachePath, File = opened };
            var node = _hostFileLru.AddFirst(entry);
            _hostFileByPath[cachePath] = node;
            file = opened;
            file.ActiveReaders = 1;
            return true;
        }
    }

    private static void ReleaseCachedHostFileV740951(CachedHostFile file)
    {
        var remaining = Interlocked.Decrement(ref file.ActiveReaders);
        if (remaining < 0)
        {
            throw new InvalidOperationException(
                "APR cached host-file lease released more than acquired.");
        }
    }

    private static void EvictAllCachedHostFilesV740951()
    {
        List<CachedHostFile> doomed = new();
        lock (_hostFileCacheGate)
        {
            var node = _hostFileLru.Last;
            while (node is not null)
            {
                var previous = node.Previous;
                if (Volatile.Read(ref node.Value.File.ActiveReaders) == 0)
                {
                    _hostFileLru.Remove(node);
                    _hostFileByPath.Remove(node.Value.Path);
                    doomed.Add(node.Value.File);
                }
                node = previous;
            }
        }

        foreach (var cached in doomed)
        {
            cached.Dispose();
        }
    }

    private static bool EvictLeastRecentlyUsedHostFileLockedV740951()
    {
        var node = _hostFileLru.Last;
        while (node is not null)
        {
            var previous = node.Previous;
            if (Volatile.Read(ref node.Value.File.ActiveReaders) == 0)
            {
                _hostFileLru.Remove(node);
                _hostFileByPath.Remove(node.Value.Path);
                node.Value.File.Dispose();
                return true;
            }
            node = previous;
        }

        return false;
    }

    private static int MeasureAmmCommand(CpuContext ctx, uint opcode, string traceName)
    {
        // The measure variant receives the six command arguments directly in
        // rdi..r9.  The encoded record is fixed-size and 16-byte aligned.
        TraceAmpr(ctx, traceName, opcode, AmmRecordSize, ctx[CpuRegister.Rdi]);
        ctx[CpuRegister.Rax] = AmmRecordSize;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int AppendAmmCommand(CpuContext ctx, uint opcode, string traceName)
    {
        var commandBuffer = ctx[CpuRegister.Rdi];
        if (commandBuffer == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        // Command-buffer variants prepend the command buffer to the same six
        // arguments used by the measure function.  SysV AMD64 therefore puts
        // the sixth payload argument at [rsp+8].
        ulong stackArgument = 0;
        if (!ctx.TryReadUInt64(ctx[CpuRegister.Rsp] + sizeof(ulong), out stackArgument))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        Span<byte> record = stackalloc byte[(int)AmmRecordSize];
        record.Clear();
        BinaryPrimitives.WriteUInt32LittleEndian(record[0x00..], AmmRecordType);
        BinaryPrimitives.WriteUInt32LittleEndian(record[0x04..], opcode);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x08..], ctx[CpuRegister.Rsi]);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x10..], ctx[CpuRegister.Rdx]);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x18..], ctx[CpuRegister.Rcx]);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x20..], ctx[CpuRegister.R8]);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x28..], ctx[CpuRegister.R9]);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x30..], stackArgument);

        if (!AppendCommandBufferRecord(ctx, commandBuffer, record))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceAmpr(
            ctx,
            traceName,
            commandBuffer,
            ctx[CpuRegister.Rsi],
            ctx[CpuRegister.Rdx]);
        ctx[CpuRegister.Rax] = 0;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static bool CompleteAmmRecord(CpuContext ctx, ulong recordAddress)
    {
        Span<byte> record = stackalloc byte[(int)AmmRecordSize];
        if (!ctx.Memory.TryRead(recordAddress, record))
        {
            return false;
        }

        var opcode = BinaryPrimitives.ReadUInt32LittleEndian(record[0x04..]);
        if (opcode < AmmOpcodeMap || opcode > AmmOpcodeUnmapToPrt)
        {
            return false;
        }

        var address = BinaryPrimitives.ReadUInt64LittleEndian(record[0x08..]);
        var length = BinaryPrimitives.ReadUInt64LittleEndian(record[0x10..]);

        // PS5 AMM commands program an I/O-side mapping aperture.  SharpEmu's
        // current memory model is unified: CPU, AMPR and GPU observe the same
        // guest backing.  Kernel direct/flexible mappings therefore provide
        // the host backing, while AMM completion only has to preserve command
        // ordering.  Do not fabricate or move CPU virtual mappings here.
        TraceAmpr(ctx, "amm_complete", opcode, address, length);
        return true;
    }

    private static bool AppendReadFileRecord(
        CpuContext ctx,
        ulong commandBuffer,
        uint fileId,
        ulong destination,
        ulong size,
        ulong fileOffset,
        ulong bytesRead)
    {
        Span<byte> record = stackalloc byte[(int)ReadFileRecordSize];
        record.Clear();
        BinaryPrimitives.WriteUInt32LittleEndian(record[0x00..], ReadFileRecordType);
        BinaryPrimitives.WriteUInt32LittleEndian(record[0x04..], fileId);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x08..], destination);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x10..], size);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x18..], fileOffset);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x20..], bytesRead);

        return AppendCommandBufferRecord(ctx, commandBuffer, record);
    }

    private static bool AppendKernelEventQueueRecord(
        CpuContext ctx,
        ulong commandBuffer,
        ulong equeue,
        ulong ident,
        ulong completionToken,
        ulong userData)
    {
        Span<byte> record = stackalloc byte[(int)KernelEventQueueRecordSize];
        record.Clear();
        BinaryPrimitives.WriteUInt32LittleEndian(record[0x00..], KernelEventQueueRecordType);
        BinaryPrimitives.WriteInt16LittleEndian(record[0x04..], KernelEventQueueCompatExports.KernelEventFilterAmpr);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x08..], equeue);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x10..], ident);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x18..], userData);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x20..], completionToken);

        return AppendCommandBufferRecord(ctx, commandBuffer, record);
    }

    private static bool AppendWriteAddressRecord(CpuContext ctx, ulong commandBuffer, ulong address, ulong value)
    {
        Span<byte> record = stackalloc byte[(int)WriteAddressRecordSize];
        record.Clear();
        BinaryPrimitives.WriteUInt32LittleEndian(record[0x00..], WriteAddressRecordType);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x08..], address);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x10..], value);

        return AppendCommandBufferRecord(ctx, commandBuffer, record);
    }

    private static bool AppendCommandBufferRecord(CpuContext ctx, ulong commandBuffer, ReadOnlySpan<byte> record)
    {
        if (!TryGetCommandBufferState(ctx, commandBuffer, out _, out _, out var state) || state is null)
        {
            return false;
        }

        var recordSize = (ulong)record.Length;
        lock (state)
        {
            if (state.Buffer == 0 ||
                state.WriteOffset > state.Size ||
                recordSize > state.Size - state.WriteOffset)
            {
                return false;
            }

            if (!ctx.Memory.TryWrite(state.Buffer + state.WriteOffset, record))
            {
                return false;
            }

            state.WriteOffset += recordSize;
            state.CommandCount++;
        }

        return true;
    }

    private static int CompleteReadFileRecord(
        CpuContext ctx,
        ulong commandBuffer,
        ulong recordAddress)
    {
        Span<byte> record = stackalloc byte[(int)ReadFileRecordSize];
        if (!ctx.Memory.TryRead(recordAddress, record))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        var fileId = BinaryPrimitives.ReadUInt32LittleEndian(record[0x04..]);
        var destination = BinaryPrimitives.ReadUInt64LittleEndian(record[0x08..]);
        var size = BinaryPrimitives.ReadUInt64LittleEndian(record[0x10..]);
        var fileOffset = BinaryPrimitives.ReadUInt64LittleEndian(record[0x18..]);

        if (!TryResolveAprHostPathV1832(fileId, out var hostPath))
        {
            // Precomputed APR ids can bypass sceKernelAprResolveFilepaths*. The
            // app0 index is therefore part of submit-time resolution, not
            // command construction. This keeps a missing id from being silently
            // converted into a successful completion watcher.
            var app0Root = KernelMemoryCompatExports.ResolveGuestPath("$/");
            if (!string.IsNullOrEmpty(app0Root))
            {
                AmprFileRegistry.EnsureApp0Indexed(app0Root);
            }

            if (!TryResolveAprHostPathV1832(fileId, out hostPath))
            {
                TraceV73016Read(
                    ref _v73016FailedReadTraceCount,
                    "APR_READ_FAILED",
                    commandBuffer,
                    fileId,
                    destination,
                    size,
                    fileOffset,
                    bytesRead: 0,
                    result: (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND,
                    hostPath);
                TraceAmprRead(
                    ctx,
                    commandBuffer,
                    fileId,
                    destination,
                    size,
                    fileOffset,
                    bytesRead: 0,
                    hostPath,
                    (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND);
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
            }
        }

        if (fileOffset == unchecked((ulong)(long)-1))
        {
            fileOffset = PakDirectoryTracker.ResolveSequentialOffset(fileId, size);
        }
        else if (fileOffset > long.MaxValue)
        {
            fileOffset = 0;
        }

        var result = TryReadFileToGuestMemory(
            ctx,
            hostPath,
            fileOffset,
            destination,
            size,
            out var bytesRead);
        if (result != (int)OrbisGen2Result.ORBIS_GEN2_OK)
        {
            TraceV73016Read(
                ref _v73016FailedReadTraceCount,
                "APR_READ_FAILED",
                commandBuffer,
                fileId,
                destination,
                size,
                fileOffset,
                bytesRead,
                result,
                hostPath);
            TraceAmprRead(
                ctx,
                commandBuffer,
                fileId,
                destination,
                size,
                fileOffset,
                bytesRead,
                hostPath,
                result);
            return result;
        }

        PakDirectoryTracker.OnReadCompleted(
            ctx, fileId, destination, fileOffset, bytesRead);

        BinaryPrimitives.WriteUInt64LittleEndian(record[0x18..], fileOffset);
        BinaryPrimitives.WriteUInt64LittleEndian(record[0x20..], bytesRead);
        if (ctx.Memory is AprSubmissionSnapshotMemory snapshotMemory)
        {
            if (!snapshotMemory.TryWriteCapturedRecord(recordAddress, record))
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }
        }
        else if (!ctx.Memory.TryWrite(recordAddress, record))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceV73016Read(
            ref _v73016CompletedReadTraceCount,
            "APR_READ_COMPLETE",
            commandBuffer,
            fileId,
            destination,
            size,
            fileOffset,
            bytesRead,
            (int)OrbisGen2Result.ORBIS_GEN2_OK,
            hostPath);

        TraceAprAssetReadV74056271(
            hostPath,
            bytesRead);

        TraceAmprRead(
            ctx,
            commandBuffer,
            fileId,
            destination,
            size,
            fileOffset,
            bytesRead,
            hostPath,
            (int)OrbisGen2Result.ORBIS_GEN2_OK);
        TracePakReadCacheV1832();
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static bool CompleteKernelEventQueueRecord(CpuContext ctx, ulong recordAddress)
    {
        Span<byte> record = stackalloc byte[(int)KernelEventQueueRecordSize];
        if (!ctx.Memory.TryRead(recordAddress, record))
        {
            return false;
        }

        var filter = unchecked((short)BinaryPrimitives.ReadUInt32LittleEndian(record[0x04..]));
        var equeue = BinaryPrimitives.ReadUInt64LittleEndian(record[0x08..]);
        var ident = BinaryPrimitives.ReadUInt64LittleEndian(record[0x10..]);
        var userData = BinaryPrimitives.ReadUInt64LittleEndian(record[0x18..]);
        var data = BinaryPrimitives.ReadUInt64LittleEndian(record[0x20..]);
        var extra = BinaryPrimitives.ReadUInt64LittleEndian(record[0x28..]);

        var queuedEvent = new KernelEventQueueCompatExports.KernelQueuedEvent(
            ident,
            filter,
            0x20,
            unchecked((uint)extra),
            data,
            userData);

        _ = KernelEventQueueCompatExports.EnqueueEvent(equeue, queuedEvent);
        TraceAmpr(ctx, "complete_equeue", equeue, ident, data);
        return true;
    }

    private static bool CompleteWriteAddressRecord(CpuContext ctx, ulong recordAddress)
    {
        Span<byte> record = stackalloc byte[(int)WriteAddressRecordSize];
        if (!ctx.Memory.TryRead(recordAddress, record))
        {
            return false;
        }

        var address = BinaryPrimitives.ReadUInt64LittleEndian(record[0x08..]);
        var value = BinaryPrimitives.ReadUInt64LittleEndian(record[0x10..]);
        if (!ctx.TryWriteUInt64(address, value))
        {
            return false;
        }

        // GPU WAIT_REG_MEM often watches these APR completion labels
        // (e.g. 0x20505xxx DEADBEEF/counter fences). Without
        // RecordProduced the wait sits producerless after the guest recycles
        // the dword, and CollectDeadlockBroken cannot replay the wake.
        _ = GpuWaitRegistry.RecordProduced(ctx.Memory, address, value);
        if ((address & 4ul) == 0)
        {
            // 32-bit GPU waits use the low dword; also latch that view when the
            // address is dword-aligned so a u32 compare against ref sees it.
            _ = GpuWaitRegistry.RecordProduced(
                ctx.Memory, address, unchecked((uint)value));
        }

        TraceAmpr(ctx, "complete_write_address", address, value, 0);
        return true;
    }

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

    private static void TryPreindexApp0()
    {
        var app0Root = KernelMemoryCompatExports.ResolveGuestPath("$/");
        if (!string.IsNullOrEmpty(app0Root))
        {
            AmprFileRegistry.EnsureApp0Indexed(app0Root);
        }
    }

    private static void TraceAmpr(CpuContext ctx, string operation, ulong commandBuffer, ulong arg0, ulong arg1)
    {
        if (!_traceAmpr)
        {
            return;
        }

        var returnRip = 0UL;
        _ = ctx.TryReadUInt64(ctx[CpuRegister.Rsp], out returnRip);
        Console.Error.WriteLine(
            $"[LOADER][TRACE] ampr.{operation}: cmd=0x{commandBuffer:X16} arg0=0x{arg0:X16} arg1=0x{arg1:X16} ret=0x{returnRip:X16}");
    }

    private static void TraceAprAssetReadV74056271(
        string? hostPath,
        ulong bytesRead)
    {
        if (!_traceAprAssetReadsV74056271 ||
            string.IsNullOrWhiteSpace(hostPath) ||
            bytesRead == 0)
        {
            return;
        }

        var extension = Path.GetExtension(hostPath);
        if (string.IsNullOrWhiteSpace(extension))
        {
            extension = "<none>";
        }

        extension = extension.ToLowerInvariant();

        var count = _aprAssetReadCountsV74056271.AddOrUpdate(
            extension,
            1,
            static (_, current) => current + 1);

        if (count > 16 &&
            (count & (count - 1)) != 0)
        {
            return;
        }

        var category = extension switch
        {
            ".ctxr" or ".ctxc" => "texture",
            ".cmsh" or ".cmdl" or ".flver" => "geometry",
            ".cmat" => "material",
            ".csdr" or ".cslt" => "shader",
            ".cgpr" or ".cfon" or ".ctxt" or ".drb" => "ui",
            ".bnk" or ".at9" => "audio",
            ".cani" or ".anibnd" => "animation",
            ".objbnd" => "object-bundle",
            _ => "other",
        };

        Console.Error.WriteLine(
            $"[V74.0.56.27.1][APR_ASSET_READ] " +
            $"ext={extension} category={category} " +
            $"count={count} bytes=0x{bytesRead:X} " +
            $"path='{hostPath}'");
    }

    private static void TraceV73016Read(
        ref long counter,
        string operation,
        ulong commandBuffer,
        uint fileId,
        ulong destination,
        ulong size,
        ulong fileOffset,
        ulong bytesRead,
        int result,
        string? hostPath)
    {
        var count = Interlocked.Increment(ref counter);
        if (count > 32 && (count & (count - 1)) != 0)
        {
            return;
        }

        Console.Error.WriteLine(
            $"[V73.0.16][{operation}] count={count} cmd=0x{commandBuffer:X16} " +
            $"id=0x{fileId:X8} dst=0x{destination:X16} size=0x{size:X} " +
            $"offset=0x{fileOffset:X} read=0x{bytesRead:X} result=0x{result:X8} " +
            $"path='{hostPath ?? string.Empty}'");
    }

        // V31.7.20_DS_INTRO_APR_SCHEDULE
    // Targeted, unsampled schedule evidence for the three audited streams.
    private static void TraceV31720DemonSoulsIntroRead(
        uint fileId,
        string? hostPath,
        ulong fileOffset,
        ulong requested,
        ulong bytesRead,
        int result)
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_INTRO_AUDIO_SCHEDULE_PROBE"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        string? stem = fileId switch
        {
            0xDC163C34u => "music",
            0xA61F4C26u => "sfx",
            0xD976DFB1u => "vo-en",
            _ => null,
        };

        if (stem is null && hostPath is not null)
        {
            if (hostPath.EndsWith(
                    "pr_demons_souls_intro_music.at9",
                    StringComparison.OrdinalIgnoreCase))
            {
                stem = "music";
            }
            else if (hostPath.EndsWith(
                         "pr_demons_souls_intro_sfx.at9",
                         StringComparison.OrdinalIgnoreCase))
            {
                stem = "sfx";
            }
            else if (hostPath.EndsWith(
                         @"\en\pr_demons_souls_intro_vo.at9",
                         StringComparison.OrdinalIgnoreCase) ||
                     hostPath.EndsWith(
                         "/en/pr_demons_souls_intro_vo.at9",
                         StringComparison.OrdinalIgnoreCase))
            {
                stem = "vo-en";
            }
        }

        if (stem is null)
        {
            return;
        }

        Console.Error.WriteLine(
            "[V31.7.20][DS_INTRO_APR_READ] " +
            $"utc='{DateTime.UtcNow:O}' " +
            $"mono_ticks={System.Diagnostics.Stopwatch.GetTimestamp()} " +
            $"stem={stem} id=0x{fileId:X8} " +
            $"offset=0x{fileOffset:X} requested=0x{requested:X} " +
            $"read=0x{bytesRead:X} result=0x{unchecked((uint)result):X8} " +
            $"path='{hostPath ?? string.Empty}'");
    }
private static void TraceAmprRead(
        CpuContext ctx,
        ulong commandBuffer,
        uint fileId,
        ulong destination,
        ulong size,
        ulong fileOffset,
        ulong bytesRead,
        string? hostPath,
        int result)
    {
        // V31.7.20.1_APR_TRACE_STRUCTURAL_HOOK
        // Must execute before the generic read trace's sampling/enable gate.
        TraceV31720DemonSoulsIntroRead(
            fileId,
            hostPath,
            fileOffset,
            size,
            bytesRead,
            result);        if (!_traceAmprReads)
        {
            return;
        }

        var returnRip = 0UL;
        _ = ctx.TryReadUInt64(ctx[CpuRegister.Rsp], out returnRip);
        Console.Error.WriteLine(
            $"[LOADER][TRACE] ampr.read_file: cmd=0x{commandBuffer:X16} id=0x{fileId:X8} dst=0x{destination:X16} size=0x{size:X16} offset=0x{fileOffset:X16} read=0x{bytesRead:X16} result=0x{result:X8} path='{hostPath ?? string.Empty}' ret=0x{returnRip:X16}");
    }
}
