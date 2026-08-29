// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace SharpEmu.Libs.Kernel;

/// <summary>
/// V76.3.6 compatibility for PS5 kernel direct-memory type and memory-pool APIs.
/// Mapper command-buffer APIs with unknown PS5 ABI are intentionally not guessed.
/// </summary>
public static partial class KernelMemoryCompatExports
{
    private const ulong MemoryPoolReserveAlignmentV7636 = 0x20_0000UL; // 2 MiB
    private const ulong MemoryPoolCommitAlignmentV7636 = 0x1_0000UL;   // 64 KiB
    private const int MemoryPoolPhysicalTypeV7636 = 3;
    private const int MemoryPoolBatchEntrySizeV7636 = 32;
    private const int MemoryPoolBatchOpcodeCommitV7636 = 1;
    private const int MemoryPoolBatchOpcodeDecommitV7636 = 2;
    private const int MemoryPoolBatchOpcodeProtectV7636 = 3;
    private const int MemoryPoolBatchOpcodeTypeProtectV7636 = 4;
    private const int MemoryPoolBatchOpcodeMoveV7636 = 5;

    private readonly record struct MemoryPoolReservationV7636(ulong Start, ulong Length);
    private readonly record struct MemoryPoolCommitRangeV7636(
        ulong Start,
        ulong Length,
        int MemoryType,
        int Protection);

    private static readonly SortedList<ulong, MemoryPoolReservationV7636>
        _memoryPoolReservationsV7636 = new();
    private static readonly List<MemoryPoolCommitRangeV7636>
        _memoryPoolCommittedRangesV7636 = new();
    private static readonly SortedList<ulong, ulong>
        _memoryPoolBackingRangesV7636 = new();

    private static ulong _memoryPoolAvailableBackingBytesV7636;
    private static ulong _memoryPoolExpandedBytesV7636;
    private static ulong _memoryPoolCommittedBytesV7636;
    private static long _memoryPoolExpandCallsV7636;
    private static long _memoryPoolReserveCallsV7636;
    private static long _memoryPoolCommitCallsV7636;
    private static long _memoryPoolDecommitCallsV7636;
    private static long _memoryPoolBatchCallsV7636;
    private static long _directMemoryTypeCallsV7636;

    private static bool KernelMemoryPoolTraceEnabledV7636 =>
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_KERNEL_POOL_LOG"),
            "1",
            StringComparison.Ordinal) ||
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_LOG_DIRECT_MEMORY"),
            "1",
            StringComparison.Ordinal);

    [SysAbiExport(
        Nid = "BC+OG5m9+bw",
        ExportName = "sceKernelGetDirectMemoryType",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelGetDirectMemoryTypeV7636(CpuContext ctx)
    {
        var address = ctx[CpuRegister.Rdi];
        var memoryTypeOut = ctx[CpuRegister.Rsi];
        var startOut = ctx[CpuRegister.Rdx];
        var endOut = ctx[CpuRegister.Rcx];
        var call = Interlocked.Increment(ref _directMemoryTypeCallsV7636);

        if (memoryTypeOut == 0 || startOut == 0 || endOut == 0)
        {
            TraceKernelMemoryPoolV7636(
                $"direct_type call={call} addr=0x{address:X16} result=invalid-output-pointer");
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        DirectAllocation allocation;
        lock (_memoryGate)
        {
            if (!TryFindDirectAllocationLocked(address, out allocation))
            {
                TraceKernelMemoryPoolV7636(
                    $"direct_type call={call} addr=0x{address:X16} result=not-found");
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
            }
        }

        var end = TryAddU64(allocation.Start, allocation.Length, out var exclusiveEnd)
            ? exclusiveEnd
            : ulong.MaxValue;

        if (!TryWriteInt32(ctx, memoryTypeOut, allocation.MemoryType) ||
            !ctx.TryWriteUInt64(startOut, allocation.Start) ||
            !ctx.TryWriteUInt64(endOut, end))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceKernelMemoryPoolV7636(
            $"direct_type call={call} addr=0x{address:X16} type={allocation.MemoryType} " +
            $"start=0x{allocation.Start:X16} end=0x{end:X16} result=ok");
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "qCSfqDILlns",
        ExportName = "sceKernelMemoryPoolExpand",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelMemoryPoolExpandV7636(CpuContext ctx)
    {
        var searchStart = ctx[CpuRegister.Rdi];
        var searchEnd = ctx[CpuRegister.Rsi];
        var length = ctx[CpuRegister.Rdx];
        var alignment = ctx[CpuRegister.Rcx];
        var physicalOut = ctx[CpuRegister.R8];
        var call = Interlocked.Increment(ref _memoryPoolExpandCallsV7636);

        if (physicalOut == 0 || searchEnd <= searchStart || length == 0 ||
            !IsAligned(length, MemoryPoolCommitAlignmentV7636) ||
            (alignment != 0 && !IsAligned(alignment, MemoryPoolCommitAlignmentV7636)))
        {
            TraceKernelMemoryPoolV7636(
                $"expand call={call} start=0x{searchStart:X} end=0x{searchEnd:X} " +
                $"len=0x{length:X} align=0x{alignment:X} result=invalid");
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        if (searchStart >= DirectMemorySizeBytes)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN;
        }

        var boundedEnd = Math.Min(searchEnd, DirectMemorySizeBytes);
        if (boundedEnd <= searchStart || boundedEnd - searchStart < length)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN;
        }

        var effectiveAlignment = alignment == 0 ? MemoryPoolCommitAlignmentV7636 : alignment;
        ulong physicalAddress;
        lock (_memoryGate)
        {
            if (!TryAllocateDirectMemoryLocked(
                    searchStart,
                    boundedEnd,
                    length,
                    effectiveAlignment,
                    MemoryPoolPhysicalTypeV7636,
                    DirectMemorySizeBytes,
                    out physicalAddress))
            {
                TraceKernelMemoryPoolV7636(
                    $"expand call={call} len=0x{length:X} result=no-backing");
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN;
            }

            _memoryPoolBackingRangesV7636[physicalAddress] = length;
            _memoryPoolAvailableBackingBytesV7636 = SaturatingAddV7636(
                _memoryPoolAvailableBackingBytesV7636,
                length);
            _memoryPoolExpandedBytesV7636 = SaturatingAddV7636(
                _memoryPoolExpandedBytesV7636,
                length);
        }

        if (!ctx.TryWriteUInt64(physicalOut, physicalAddress))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceKernelMemoryPoolV7636(
            $"expand call={call} phys=0x{physicalAddress:X16} len=0x{length:X} " +
            $"available_mb={_memoryPoolAvailableBackingBytesV7636 / (1024 * 1024)} result=ok");
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "pU-QydtGcGY",
        ExportName = "sceKernelMemoryPoolReserve",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelMemoryPoolReserveV7636(CpuContext ctx)
    {
        var requestedAddress = ctx[CpuRegister.Rdi];
        var length = ctx[CpuRegister.Rsi];
        var alignment = ctx[CpuRegister.Rdx];
        var flags = unchecked((int)ctx[CpuRegister.Rcx]);
        var addressOut = ctx[CpuRegister.R8];
        var call = Interlocked.Increment(ref _memoryPoolReserveCallsV7636);

        if (addressOut == 0 || length == 0 ||
            !IsAligned(length, MemoryPoolReserveAlignmentV7636) ||
            (alignment != 0 &&
             (!IsPowerOfTwoV7636(alignment) && !IsAligned(alignment, MemoryPoolReserveAlignmentV7636))))
        {
            TraceKernelMemoryPoolV7636(
                $"reserve call={call} requested=0x{requestedAddress:X16} len=0x{length:X} " +
                $"align=0x{alignment:X} flags=0x{flags:X8} result=invalid");
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        var effectiveAlignment = alignment == 0 ? MemoryPoolReserveAlignmentV7636 : alignment;
        var fixedMapping = (flags & OrbisKernelMapFixed) != 0;
        if (fixedMapping && requestedAddress == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        var desired = requestedAddress != 0
            ? requestedAddress
            : AlignUp(
                _nextVirtualAddress == 0 ? DefaultMapSearchBase : _nextVirtualAddress,
                effectiveAlignment);

        ulong mappedAddress;
        lock (_memoryGate)
        {
            var reserved = KernelVirtualRangeAllocator.TryReserve(
                ctx,
                desired,
                length,
                executable: false,
                alignment: effectiveAlignment,
                allowSearch: !fixedMapping,
                allowAllocateAtAlternative: false,
                traceName: "memory pool reserve",
                out mappedAddress,
                backPartialOverlap: false);

            if (!reserved || mappedAddress == 0 || !TryProtectHostRange(mappedAddress, length, 0))
            {
                TraceKernelMemoryPoolV7636(
                    $"reserve call={call} desired=0x{desired:X16} len=0x{length:X} result=no-range");
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN;
            }

            _memoryPoolReservationsV7636[mappedAddress] =
                new MemoryPoolReservationV7636(mappedAddress, length);
            _nextVirtualAddress = Math.Max(_nextVirtualAddress, mappedAddress + length);
            ReplaceMappedRegionRangeLocked(new MappedRegion(
                mappedAddress,
                length,
                Protection: 0,
                IsFlexible: false,
                IsDirect: false,
                DirectStart: 0,
                MemoryType: 0));
            _mappedRegionNames[mappedAddress] = "memory-pool-reserved";
        }

        if (!ctx.TryWriteUInt64(addressOut, mappedAddress))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceKernelMemoryPoolV7636(
            $"reserve call={call} requested=0x{requestedAddress:X16} mapped=0x{mappedAddress:X16} " +
            $"len=0x{length:X} align=0x{effectiveAlignment:X} flags=0x{flags:X8} result=ok");
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    [SysAbiExport(
        Nid = "Vzl66WmfLvk",
        ExportName = "sceKernelMemoryPoolCommit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelMemoryPoolCommitV7636(CpuContext ctx) =>
        MemoryPoolCommitCoreV7636(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            unchecked((int)ctx[CpuRegister.Rcx]),
            unchecked((int)ctx[CpuRegister.R8]),
            traceCall: true);

    [SysAbiExport(
        Nid = "LXo1tpFqJGs",
        ExportName = "sceKernelMemoryPoolDecommit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelMemoryPoolDecommitV7636(CpuContext ctx) =>
        MemoryPoolDecommitCoreV7636(
            ctx,
            ctx[CpuRegister.Rdi],
            ctx[CpuRegister.Rsi],
            unchecked((int)ctx[CpuRegister.Rdx]),
            traceCall: true);

    [SysAbiExport(
        Nid = "YN878uKRBbE",
        ExportName = "sceKernelMemoryPoolBatch",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelMemoryPoolBatchV7636(CpuContext ctx)
    {
        var entriesAddress = ctx[CpuRegister.Rdi];
        var count = unchecked((int)ctx[CpuRegister.Rsi]);
        var processedOut = ctx[CpuRegister.Rdx];
        var batchFlags = unchecked((int)ctx[CpuRegister.Rcx]);
        var call = Interlocked.Increment(ref _memoryPoolBatchCallsV7636);

        if (entriesAddress == 0 || count < 0 || count > 1_000_000)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        var processed = 0;
        var result = (int)OrbisGen2Result.ORBIS_GEN2_OK;
        for (var index = 0; index < count; index++)
        {
            var entryAddress = entriesAddress + ((ulong)index * MemoryPoolBatchEntrySizeV7636);
            Span<byte> entry = stackalloc byte[MemoryPoolBatchEntrySizeV7636];
            if (!TryReadCompat(ctx, entryAddress, entry))
            {
                result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
                break;
            }

            var opcode = unchecked((int)BinaryPrimitives.ReadUInt32LittleEndian(entry[0..4]));
            var entryFlags = unchecked((int)BinaryPrimitives.ReadUInt32LittleEndian(entry[4..8]));
            var address = BinaryPrimitives.ReadUInt64LittleEndian(entry[8..16]);
            var length = BinaryPrimitives.ReadUInt64LittleEndian(entry[16..24]);
            var protection = entry[24];
            var memoryType = entry[25];

            result = opcode switch
            {
                MemoryPoolBatchOpcodeCommitV7636 => MemoryPoolCommitCoreV7636(
                    ctx, address, length, memoryType, protection, entryFlags, traceCall: false),
                MemoryPoolBatchOpcodeDecommitV7636 => MemoryPoolDecommitCoreV7636(
                    ctx, address, length, entryFlags, traceCall: false),
                MemoryPoolBatchOpcodeProtectV7636 => InvokeKernelMemoryOperation(
                    ctx, KernelMprotect, address, length, unchecked((ulong)protection)),
                MemoryPoolBatchOpcodeTypeProtectV7636 => InvokeKernelMemoryOperation(
                    ctx, KernelMtypeprotect, address, length, unchecked((ulong)memoryType),
                    unchecked((ulong)protection)),
                MemoryPoolBatchOpcodeMoveV7636 => (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_IMPLEMENTED,
                _ => (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT,
            };

            if (result != (int)OrbisGen2Result.ORBIS_GEN2_OK)
            {
                break;
            }
            processed++;
        }

        if (processedOut != 0 && !TryWriteInt32(ctx, processedOut, processed))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceKernelMemoryPoolV7636(
            $"batch call={call} count={count} processed={processed} batch_flags=0x{batchFlags:X8} " +
            $"result=0x{unchecked((uint)result):X8}");
        return result;
    }

    [SysAbiExport(
        Nid = "bvD+95Q6asU",
        ExportName = "sceKernelMemoryPoolGetBlockStats",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libKernel")]
    public static int KernelMemoryPoolGetBlockStatsV7636(CpuContext ctx)
    {
        var statsAddress = ctx[CpuRegister.Rdi];
        var size = ctx[CpuRegister.Rsi];
        if (size != 0 && statsAddress == 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        ulong available;
        ulong committed;
        lock (_memoryGate)
        {
            available = _memoryPoolAvailableBackingBytesV7636;
            committed = _memoryPoolCommittedBytesV7636;
        }

        Span<byte> stats = stackalloc byte[16];
        stats.Clear();
        // SharpEmu does not model the hardware flushed-vs-cached distinction.
        // Keep cached counters zero rather than inventing a host cache policy.
        BinaryPrimitives.WriteInt32LittleEndian(
            stats[0..4], ClampBlockCountV7636(available / MemoryPoolCommitAlignmentV7636));
        BinaryPrimitives.WriteInt32LittleEndian(stats[4..8], 0);
        BinaryPrimitives.WriteInt32LittleEndian(
            stats[8..12], ClampBlockCountV7636(committed / MemoryPoolCommitAlignmentV7636));
        BinaryPrimitives.WriteInt32LittleEndian(stats[12..16], 0);

        var bytesToWrite = (int)Math.Min(size, (ulong)stats.Length);
        if (bytesToWrite != 0 && !TryWriteCompat(ctx, statsAddress, stats[..bytesToWrite]))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        TraceKernelMemoryPoolV7636(
            $"stats available_blocks={available / MemoryPoolCommitAlignmentV7636} " +
            $"committed_blocks={committed / MemoryPoolCommitAlignmentV7636} size={size}");
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int MemoryPoolCommitCoreV7636(
        CpuContext ctx,
        ulong address,
        ulong length,
        int memoryType,
        int protection,
        int flags,
        bool traceCall)
    {
        var call = traceCall
            ? Interlocked.Increment(ref _memoryPoolCommitCallsV7636)
            : Volatile.Read(ref _memoryPoolCommitCallsV7636);

        if (address == 0 || length == 0 ||
            !IsAligned(length, MemoryPoolCommitAlignmentV7636) ||
            (protection & OrbisProtCpuExec) != 0)
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        lock (_memoryGate)
        {
            if (!TryFindMemoryPoolReservationContainingLockedV7636(address, length, out _) ||
                HasMemoryPoolCommittedOverlapLockedV7636(address, length))
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
            }

            if (_memoryPoolAvailableBackingBytesV7636 < length)
            {
                TraceKernelMemoryPoolV7636(
                    $"commit call={call} addr=0x{address:X16} len=0x{length:X} " +
                    $"available=0x{_memoryPoolAvailableBackingBytesV7636:X} result=no-backing");
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_TRY_AGAIN;
            }

            if (!TryProtectHostRange(address, length, protection) ||
                !TryApplyMappedRegionProtectionLocked(address, length, protection, memoryType))
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
            }

            AddMemoryPoolCommittedRangeLockedV7636(
                new MemoryPoolCommitRangeV7636(address, length, memoryType, protection));
            _memoryPoolAvailableBackingBytesV7636 -= length;
            _memoryPoolCommittedBytesV7636 = SaturatingAddV7636(_memoryPoolCommittedBytesV7636, length);
        }

        if (traceCall)
        {
            TraceKernelMemoryPoolV7636(
                $"commit call={call} addr=0x{address:X16} len=0x{length:X} type={memoryType} " +
                $"prot=0x{protection:X2} flags=0x{flags:X8} " +
                $"available_mb={_memoryPoolAvailableBackingBytesV7636 / (1024 * 1024)} result=ok");
        }
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int MemoryPoolDecommitCoreV7636(
        CpuContext ctx,
        ulong address,
        ulong length,
        int flags,
        bool traceCall)
    {
        var call = traceCall
            ? Interlocked.Increment(ref _memoryPoolDecommitCallsV7636)
            : Volatile.Read(ref _memoryPoolDecommitCallsV7636);

        if (address == 0 || length == 0 ||
            !IsAligned(length, MemoryPoolCommitAlignmentV7636))
        {
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        ulong restoredBacking;
        lock (_memoryGate)
        {
            if (!TryFindMemoryPoolReservationContainingLockedV7636(address, length, out _))
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
            }

            if (!TryProtectHostRange(address, length, 0) ||
                !TryApplyMappedRegionProtectionLocked(address, length, 0, memoryType: 0))
            {
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
            }

            restoredBacking = RemoveMemoryPoolCommittedCoverageLockedV7636(address, length);
            _memoryPoolAvailableBackingBytesV7636 = SaturatingAddV7636(
                _memoryPoolAvailableBackingBytesV7636, restoredBacking);
            _memoryPoolCommittedBytesV7636 = restoredBacking >= _memoryPoolCommittedBytesV7636
                ? 0
                : _memoryPoolCommittedBytesV7636 - restoredBacking;
        }

        if (traceCall)
        {
            TraceKernelMemoryPoolV7636(
                $"decommit call={call} addr=0x{address:X16} len=0x{length:X} flags=0x{flags:X8} " +
                $"returned=0x{restoredBacking:X} result=ok");
        }
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static bool TryFindMemoryPoolReservationContainingLockedV7636(
        ulong address,
        ulong length,
        out MemoryPoolReservationV7636 reservation)
    {
        reservation = default;
        if (length == 0 || !TryAddU64(address, length, out var end))
        {
            return false;
        }

        foreach (var candidate in _memoryPoolReservationsV7636.Values)
        {
            if (!TryAddU64(candidate.Start, candidate.Length, out var candidateEnd))
            {
                continue;
            }
            if (address >= candidate.Start && end <= candidateEnd)
            {
                reservation = candidate;
                return true;
            }
        }
        return false;
    }

    private static bool HasMemoryPoolCommittedOverlapLockedV7636(ulong address, ulong length)
    {
        if (!TryAddU64(address, length, out var end))
        {
            return true;
        }
        foreach (var range in _memoryPoolCommittedRangesV7636)
        {
            var rangeEnd = range.Start + range.Length;
            if (range.Start < end && rangeEnd > address)
            {
                return true;
            }
        }
        return false;
    }

    private static bool IsMemoryPoolRangeFullyCommittedLockedV7636(ulong address, ulong length)
    {
        if (!TryAddU64(address, length, out var end))
        {
            return false;
        }

        var cursor = address;
        foreach (var range in _memoryPoolCommittedRangesV7636.OrderBy(static item => item.Start))
        {
            var rangeEnd = range.Start + range.Length;
            if (rangeEnd <= cursor)
            {
                continue;
            }
            if (range.Start > cursor)
            {
                return false;
            }
            cursor = Math.Min(end, rangeEnd);
            if (cursor == end)
            {
                return true;
            }
        }
        return false;
    }

    private static void AddMemoryPoolCommittedRangeLockedV7636(MemoryPoolCommitRangeV7636 range)
    {
        _memoryPoolCommittedRangesV7636.Add(range);
        _memoryPoolCommittedRangesV7636.Sort(static (left, right) => left.Start.CompareTo(right.Start));
        CoalesceMemoryPoolCommittedRangesLockedV7636();
    }

    private static ulong RemoveMemoryPoolCommittedCoverageLockedV7636(ulong address, ulong length)
    {
        if (!TryAddU64(address, length, out var end))
        {
            return 0;
        }

        ulong removed = 0;
        var replacement = new List<MemoryPoolCommitRangeV7636>();
        foreach (var range in _memoryPoolCommittedRangesV7636)
        {
            var rangeEnd = range.Start + range.Length;
            var overlapStart = Math.Max(address, range.Start);
            var overlapEnd = Math.Min(end, rangeEnd);
            if (overlapStart >= overlapEnd)
            {
                replacement.Add(range);
                continue;
            }

            removed = SaturatingAddV7636(removed, overlapEnd - overlapStart);
            if (range.Start < overlapStart)
            {
                replacement.Add(range with { Length = overlapStart - range.Start });
            }
            if (overlapEnd < rangeEnd)
            {
                replacement.Add(range with { Start = overlapEnd, Length = rangeEnd - overlapEnd });
            }
        }

        _memoryPoolCommittedRangesV7636.Clear();
        _memoryPoolCommittedRangesV7636.AddRange(replacement.OrderBy(static item => item.Start));
        CoalesceMemoryPoolCommittedRangesLockedV7636();
        return removed;
    }

    private static void UpdateMemoryPoolCommittedAttributesLockedV7636(
        ulong address,
        ulong length,
        int protection,
        int? memoryType)
    {
        if (!TryAddU64(address, length, out var end))
        {
            return;
        }

        var replacement = new List<MemoryPoolCommitRangeV7636>();
        foreach (var range in _memoryPoolCommittedRangesV7636)
        {
            var rangeEnd = range.Start + range.Length;
            var overlapStart = Math.Max(address, range.Start);
            var overlapEnd = Math.Min(end, rangeEnd);
            if (overlapStart >= overlapEnd)
            {
                replacement.Add(range);
                continue;
            }

            if (range.Start < overlapStart)
            {
                replacement.Add(range with { Length = overlapStart - range.Start });
            }
            replacement.Add(new MemoryPoolCommitRangeV7636(
                overlapStart,
                overlapEnd - overlapStart,
                memoryType ?? range.MemoryType,
                protection));
            if (overlapEnd < rangeEnd)
            {
                replacement.Add(range with { Start = overlapEnd, Length = rangeEnd - overlapEnd });
            }
        }

        _memoryPoolCommittedRangesV7636.Clear();
        _memoryPoolCommittedRangesV7636.AddRange(replacement.OrderBy(static item => item.Start));
        CoalesceMemoryPoolCommittedRangesLockedV7636();
    }

    private static void CoalesceMemoryPoolCommittedRangesLockedV7636()
    {
        if (_memoryPoolCommittedRangesV7636.Count < 2)
        {
            return;
        }

        var merged = new List<MemoryPoolCommitRangeV7636>(_memoryPoolCommittedRangesV7636.Count);
        foreach (var range in _memoryPoolCommittedRangesV7636.OrderBy(static item => item.Start))
        {
            if (merged.Count == 0)
            {
                merged.Add(range);
                continue;
            }

            var previous = merged[^1];
            var previousEnd = previous.Start + previous.Length;
            if (previousEnd == range.Start &&
                previous.MemoryType == range.MemoryType &&
                previous.Protection == range.Protection)
            {
                merged[^1] = previous with { Length = previous.Length + range.Length };
            }
            else
            {
                merged.Add(range);
            }
        }

        _memoryPoolCommittedRangesV7636.Clear();
        _memoryPoolCommittedRangesV7636.AddRange(merged);
    }

    internal static (bool IsPooled, bool IsCommitted) GetMemoryPoolVirtualStateV7636(
        ulong address,
        ulong length)
    {
        lock (_memoryGate)
        {
            var pooled = TryFindMemoryPoolReservationContainingLockedV7636(address, length, out _);
            return pooled
                ? (true, IsMemoryPoolRangeFullyCommittedLockedV7636(address, length))
                : (false, false);
        }
    }

    private static bool IsPowerOfTwoV7636(ulong value) =>
        value != 0 && (value & (value - 1)) == 0;

    private static ulong SaturatingAddV7636(ulong left, ulong right) =>
        ulong.MaxValue - left < right ? ulong.MaxValue : left + right;

    private static int ClampBlockCountV7636(ulong value) =>
        value > int.MaxValue ? int.MaxValue : (int)value;

    private static void TraceKernelMemoryPoolV7636(string message)
    {
        if (!KernelMemoryPoolTraceEnabledV7636)
        {
            return;
        }
        Console.Error.WriteLine($"[KERNEL-POOL][V76.3.6] {message}");
    }
}
