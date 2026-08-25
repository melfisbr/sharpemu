// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using SharpEmu.Core.Loader;
using SharpEmu.HLE;
using SharpEmu.HLE.Host;
using SharpEmu.Logging;
using SharpEmu.Libs.Gpu; // SHARPEMU_V74_0_117_8_GUEST_MEMORY_PROVENANCE_PROPAGATION

namespace SharpEmu.Core.Memory;

public sealed unsafe class PhysicalVirtualMemory : IVirtualMemory, IGuestMemoryAllocator, IGuestAddressSpace, IDisposable
{
    private static readonly SharpEmuLogger Log = SharpEmuLog.For("VMEM");

    private readonly ReaderWriterLockSlim _gate = new(LockRecursionPolicy.SupportsRecursion);
    private readonly object _guestAllocationGate = new();
    private readonly object _allocationSearchHintGate = new();
    private readonly List<MemoryRegion> _regions = new();
    private readonly Dictionary<(ulong DesiredAddress, ulong Alignment, bool Executable), ulong> _allocationSearchHints = new();
    private readonly ConcurrentDictionary<ulong, ProgramHeaderFlags> _pageProtections = new();
    private bool _disposed;

    [ThreadStatic]
    private static CommittedRangeCache? _committedRangeCache;

    // SHARPEMU_V74_0_91_MEMCPY_REGION_CACHE
    // ResourcePool startup performs millions of tiny libc memcpy calls. Cache
    // region lookup + page-access results per native guest thread, invalidated
    // whenever mappings or tracked page protections change. The VM read lock is
    // intentionally preserved, so mapping lifetime/order semantics do not change.
    [ThreadStatic]
    private static CopyRegionAccessCacheV91? _copyRegionAccessCacheV91;
    private long _protectionGenerationV91;

    // SHARPEMU_V74_0_117_11_SHADER_GLOBAL_READ_PVM_ACCESS_CACHE
    // Shader global-buffer snapshots repeatedly probe large guest ranges. Cache
    // only address->region and verified read-permission ranges; bytes are NEVER
    // cached. Mapping/protection generations invalidate every entry and the
    // existing VM read lock remains held while live bytes are copied.
    private static readonly bool _shaderLargeReadAccessCacheV11711 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE"),
            "1",
            StringComparison.Ordinal);
    private const int ShaderLargeReadCacheSlotsV11711 = 64;
    private const int ShaderLargeReadMinimumBytesV11711 = 4096;

    [ThreadStatic]
    private static LargeReadAccessCacheV11711? _largeReadAccessCacheV11711;

    public static long V11711LargeReadCalls;
    public static long V11711RegionHits;
    public static long V11711RegionMisses;
    public static long V11711ExtentRejects;
    public static long V11711AccessHits;
    public static long V11711AccessMisses;
    public static long V11711LiveCopies;
    public static long V11711RequestedBytes;
    public static long V11711PagesBypassed;

    private sealed class LargeReadAccessCacheV11711
    {
        internal PhysicalVirtualMemory? Owner;
        internal long MappingGeneration;
        internal long ProtectionGeneration;
        internal readonly MemoryRegion?[] Regions =
            new MemoryRegion?[ShaderLargeReadCacheSlotsV11711];
        internal readonly ulong[] ReadStartPages =
            new ulong[ShaderLargeReadCacheSlotsV11711];
        internal readonly ulong[] ReadEndPages =
            new ulong[ShaderLargeReadCacheSlotsV11711];

        internal void Reset(
            PhysicalVirtualMemory owner,
            long mappingGeneration,
            long protectionGeneration)
        {
            Owner = owner;
            MappingGeneration = mappingGeneration;
            ProtectionGeneration = protectionGeneration;
            Array.Clear(Regions, 0, Regions.Length);
            Array.Clear(ReadStartPages, 0, ReadStartPages.Length);
            Array.Clear(ReadEndPages, 0, ReadEndPages.Length);
        }
    }

    // SHARPEMU_VMEM_COPY_REGION_CACHE_V1_8_40
    [ThreadStatic]
    private static CopyRegionPairCacheV1840? _copyRegionPairCacheV1840;

    [ThreadStatic]
    private static long _copyRegionPairCacheHitCountV1840;

    [ThreadStatic]
    private static long _copyRegionPairCacheMissCountV1840;

    private static readonly bool _traceCopyRegionPairCacheV1840 =
        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_TRACE_DBFZ_MEMCPY_CACHE"), "1", StringComparison.Ordinal);

    private sealed class CopyRegionPairCacheV1840
    {
        public PhysicalVirtualMemory? Owner;
        public long Generation;
        public MemoryRegion? SourceRegion;
        public MemoryRegion? DestinationRegion;
    }
    private long _mappingGeneration;
    private const ulong PageSize = 0x1000;
    private const ulong HostAllocationGranularity = 0x10000;
    private const ulong GuestAllocationArenaAddress = 0x00006000_0000_0000;
    private const ulong GuestAllocationArenaSize = 0x0100_0000;
    private const ulong GuestAllocationArenaStartOffset = PageSize;
    private const ulong LargeDataReserveThreshold = 0x4000_0000UL; // 1 GiB
    private const ulong FullCommitRegionLimit = 4UL << 30;
    private const ulong DefaultLazyReservePrimeBytes = 0x0400_0000UL; // 64 MiB
    private const ulong LazyReservePrimeChunkBytes = 0x0200_0000UL; // 32 MiB
    private const int CommittedRangeCacheCapacity = 4;

    private sealed class CommittedRangeCache
    {
        private readonly CommittedRange[] _ranges = new CommittedRange[CommittedRangeCacheCapacity];
        private PhysicalVirtualMemory? _owner;
        private long _generation;
        private int _count;
        private int _nextReplacement;

        public bool Contains(
            PhysicalVirtualMemory owner,
            long generation,
            ulong start,
            ulong end)
        {
            if (!ReferenceEquals(_owner, owner) || _generation != generation)
            {
                return false;
            }

            for (var index = 0; index < _count; index++)
            {
                var range = _ranges[index];
                if (start >= range.Start && end <= range.End)
                {
                    return true;
                }
            }

            return false;
        }

        public void Add(
            PhysicalVirtualMemory owner,
            long generation,
            ulong start,
            ulong end)
        {
            if (!ReferenceEquals(_owner, owner) || _generation != generation)
            {
                _owner = owner;
                _generation = generation;
                _count = 0;
                _nextReplacement = 0;
            }

            for (var index = 0; index < _count; index++)
            {
                var range = _ranges[index];
                if (start <= range.End && end >= range.Start)
                {
                    _ranges[index] = new CommittedRange(
                        Math.Min(start, range.Start),
                        Math.Max(end, range.End));
                    return;
                }
            }

            if (_count < _ranges.Length)
            {
                _ranges[_count++] = new CommittedRange(start, end);
                return;
            }

            _ranges[_nextReplacement] = new CommittedRange(start, end);
            _nextReplacement = (_nextReplacement + 1) % _ranges.Length;
        }
    }

    private sealed class CopyRegionAccessCacheV91
    {
        public PhysicalVirtualMemory? Owner;
        public long MappingGeneration;
        public long ProtectionGeneration;
        public MemoryRegion? SourceRegion;
        public MemoryRegion? DestinationRegion;
        public MemoryRegion? ReadAccessRegion;
        public ulong ReadAccessStartPage;
        public ulong ReadAccessEndPage;
        public MemoryRegion? WriteAccessRegion;
        public ulong WriteAccessStartPage;
        public ulong WriteAccessEndPage;

        public void Reset(PhysicalVirtualMemory owner, long mappingGeneration, long protectionGeneration)
        {
            Owner = owner;
            MappingGeneration = mappingGeneration;
            ProtectionGeneration = protectionGeneration;
            SourceRegion = null;
            DestinationRegion = null;
            ReadAccessRegion = null;
            WriteAccessRegion = null;
            ReadAccessStartPage = ReadAccessEndPage = 0;
            WriteAccessStartPage = WriteAccessEndPage = 0;
        }
    }

    private readonly record struct CommittedRange(ulong Start, ulong End);

    // Raw Windows PAGE_* values retained for the internal region/protection
    // bookkeeping: regions and saved old-protection values always carry the raw
    // value of the host platform in use, and these classification helpers only
    // ever see values this class itself assigned (see IHostMemory.ProtectRaw).
    private const uint PAGE_EXECUTE_READ = 0x20;
    private const uint PAGE_EXECUTE_READWRITE = 0x40;
    private const uint PAGE_EXECUTE = 0x10;
    private const uint PAGE_EXECUTE_WRITECOPY = 0x80;
    private const uint PAGE_READWRITE = 0x04;
    private const uint PAGE_READONLY = 0x02;

    private readonly IHostMemory _hostMemory;

    private readonly object _fixedAllocationGate = new();
    private readonly HashSet<ulong> _fixedGranuleReservationBases = new();
    private ulong _guestAllocationArenaBase;
    private readonly SortedDictionary<ulong, ulong> _guestAllocationFreeRanges = new();
    private readonly Dictionary<ulong, (ulong Offset, ulong Size)> _guestAllocations = new();
    private static readonly ulong LazyReservePrimeBytes = ResolveLazyReservePrimeBytes();

    public PhysicalVirtualMemory(IHostMemory? hostMemory = null)
    {
        _hostMemory = hostMemory ?? CrossPlatformHostMemory.Instance;
    }

    private sealed class CrossPlatformHostMemory : IHostMemory
    {
        public static readonly CrossPlatformHostMemory Instance = new();

        public ulong Allocate(ulong desiredAddress, ulong size, HostPageProtection protection) =>
            unchecked((ulong)HostMemory.Alloc(
                (void*)desiredAddress,
                (nuint)size,
                HostMemory.MEM_RESERVE | HostMemory.MEM_COMMIT,
                ToRawProtection(protection)));

        public ulong Reserve(ulong desiredAddress, ulong size, HostPageProtection protection) =>
            unchecked((ulong)HostMemory.Alloc(
                (void*)desiredAddress,
                (nuint)size,
                HostMemory.MEM_RESERVE,
                ToRawProtection(protection)));

        public bool Commit(ulong address, ulong size, HostPageProtection protection) =>
            HostMemory.Alloc(
                (void*)address,
                (nuint)size,
                HostMemory.MEM_COMMIT,
                ToRawProtection(protection)) != null;

        public bool Free(ulong address) =>
            HostMemory.Free((void*)address, 0, HostMemory.MEM_RELEASE);

        public bool Protect(
            ulong address,
            ulong size,
            HostPageProtection protection,
            out uint rawOldProtection) =>
            HostMemory.Protect(
                (void*)address,
                (nuint)size,
                ToRawProtection(protection),
                out rawOldProtection);

        public bool ProtectRaw(
            ulong address,
            ulong size,
            uint rawProtection,
            out uint rawOldProtection) =>
            HostMemory.Protect((void*)address, (nuint)size, rawProtection, out rawOldProtection);

        public bool Query(ulong address, out HostRegionInfo info)
        {
            if (HostMemory.Query((void*)address, out var raw) == 0)
            {
                info = default;
                return false;
            }

            var state = raw.State switch
            {
                HostMemory.MEM_FREE_STATE => HostRegionState.Free,
                HostMemory.MEM_RESERVE => HostRegionState.Reserved,
                _ => HostRegionState.Committed,
            };

            info = new HostRegionInfo(
                raw.BaseAddress,
                raw.AllocationBase,
                raw.RegionSize,
                state,
                raw.State,
                FromRawProtection(raw.Protect),
                raw.Protect,
                raw.AllocationProtect);
            return true;
        }

        public void FlushInstructionCache(ulong address, ulong size) =>
            HostMemory.FlushInstructionCache((void*)address, (nuint)size);

        private static uint ToRawProtection(HostPageProtection protection) => protection switch
        {
            HostPageProtection.NoAccess => HostMemory.PAGE_NOACCESS,
            HostPageProtection.ReadOnly => HostMemory.PAGE_READONLY,
            HostPageProtection.ReadWrite => HostMemory.PAGE_READWRITE,
            HostPageProtection.Execute => HostMemory.PAGE_EXECUTE,
            HostPageProtection.ReadExecute => HostMemory.PAGE_EXECUTE_READ,
            HostPageProtection.ReadWriteExecute => HostMemory.PAGE_EXECUTE_READWRITE,
            HostPageProtection.ExecuteWriteCopy => 0x80,
            _ => HostMemory.PAGE_NOACCESS,
        };

        private static HostPageProtection FromRawProtection(uint protection) => protection switch
        {
            HostMemory.PAGE_READONLY => HostPageProtection.ReadOnly,
            HostMemory.PAGE_READWRITE => HostPageProtection.ReadWrite,
            HostMemory.PAGE_EXECUTE => HostPageProtection.Execute,
            HostMemory.PAGE_EXECUTE_READ => HostPageProtection.ReadExecute,
            HostMemory.PAGE_EXECUTE_READWRITE => HostPageProtection.ReadWriteExecute,
            0x80 => HostPageProtection.ExecuteWriteCopy,
            _ => HostPageProtection.NoAccess,
        };
    }

    // SHARPEMU_V74_0_56_32_LOADER_SPARSE_RESERVATION
    //
    // Reserve the complete ELF image window without committing every page.
    // PT_LOAD segments are committed on demand by MapLoaderSegment. This avoids
    // paying commit/zero-fill cost for address-space holes and large BSS ranges
    // before the guest can possibly touch them.
    public bool TryReserveLoaderImageAtExact(
        ulong desiredAddress,
        ulong size,
        bool executable,
        out ulong actualAddress)
    {
        actualAddress = 0;
        if (size == 0)
        {
            return false;
        }

        var alignedSize = AlignUp(size, PageSize);
        var hostProtection = executable
            ? HostPageProtection.ReadWriteExecute
            : HostPageProtection.ReadWrite;
        var result = _hostMemory.Reserve(desiredAddress, alignedSize, hostProtection);
        if (result == 0)
        {
            return false;
        }

        if (result != desiredAddress)
        {
            _hostMemory.Free(result);
            return false;
        }

        _gate.EnterWriteLock();
        try
        {
            InsertRegionSorted(new MemoryRegion
            {
                VirtualAddress = result,
                Size = alignedSize,
                IsExecutable = executable,
                IsReservedOnly = true,
                Protection = executable ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE
            });
        }
        finally
        {
            _gate.ExitWriteLock();
        }

        Interlocked.Increment(ref _mappingGeneration);
        actualAddress = result;
        TraceVmem(
            $"Reserved sparse loader image: 0x{result:X16} - 0x{result + alignedSize:X16} " +
            $"({alignedSize} bytes, executable={executable})");
        return true;
    }

    public bool TryAllocateAtExact(ulong desiredAddress, ulong size, bool executable, out ulong actualAddress)
    {
        actualAddress = 0;
        if (size == 0)
        {
            return false;
        }

        var alignedSize = (size + 0xFFF) & ~0xFFFUL;
        var protection = executable ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE;
        var hostProtection = executable ? HostPageProtection.ReadWriteExecute : HostPageProtection.ReadWrite;
        var allowLazyReserve = !executable &&
            alignedSize >= LargeDataReserveThreshold &&
            alignedSize > FullCommitRegionLimit;

        // Commit first so titles that walk guest memory via raw host pointers
        // (GTA post-RenderThread workers) keep fully backed pages. Fall back to
        // reserve-only + lazy commit only when a huge non-exec commit fails —
        // that is the Poppy / large-reservation path #608 was aiming for.
        var reservedOnly = false;
        var result = TryAllocateFixedThroughGranules(desiredAddress, alignedSize, hostProtection, traceReject: false);
        if (result == 0)
        {
            result = _hostMemory.Allocate(desiredAddress, alignedSize, hostProtection);
        }

        if (result == 0 && allowLazyReserve)
        {
            result = _hostMemory.Reserve(desiredAddress, alignedSize, HostPageProtection.ReadWrite);
            reservedOnly = result != 0;
        }

        if (result == 0)
        {
            return false;
        }

        actualAddress = result;
        if (actualAddress != desiredAddress)
        {
            _hostMemory.Free(result);
            actualAddress = 0;
            return false;
        }

        var lazyPrimeState = reservedOnly ? PrimeLazyReserveRegion(actualAddress, alignedSize) : "n/a";

        _gate.EnterWriteLock();
        try
        {
            InsertRegionSorted(new MemoryRegion
            {
                VirtualAddress = actualAddress,
                Size = alignedSize,
                IsExecutable = executable,
                IsReservedOnly = reservedOnly,
                Protection = protection
            });
        }
        finally
        {
            _gate.ExitWriteLock();
        }

        var allocationKind = reservedOnly
            ? "reserved data memory (lazy commit)"
            : (executable ? "executable memory" : "data memory");
        TraceVmem(
            $"Allocated exact {allocationKind}: 0x{actualAddress:X16} - 0x{actualAddress + alignedSize:X16} " +
            $"({alignedSize} bytes) lazy_prime={lazyPrimeState}");
        return true;
    }

    public string DescribeAddressForDiagnostics(ulong address)
    {
        if (!_hostMemory.Query(address, out var info))
        {
            return "unable to query host memory at this address";
        }

        return info.State switch
        {
            HostRegionState.Free => "address reports free, but the exact-address reservation still failed",
            HostRegionState.Reserved =>
                $"already reserved by another host allocation (base=0x{info.AllocationBase:X16}, size=0x{info.RegionSize:X})",
            HostRegionState.Committed =>
                $"already committed by another host allocation (base=0x{info.AllocationBase:X16}, size=0x{info.RegionSize:X}, protect=0x{info.RawProtection:X})",
            _ => $"in an unexpected host state (raw=0x{info.RawState:X})",
        };
    }

    public ulong AllocateAt(ulong desiredAddress, ulong size, bool executable = true, bool allowAlternative = true)
    {
        if (size == 0)
            throw new ArgumentOutOfRangeException(nameof(size), "Size must be greater than zero");

        var alignedSize = (size + 0xFFF) & ~0xFFFUL;

        var protection = executable ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE;
        var hostProtection = executable ? HostPageProtection.ReadWriteExecute : HostPageProtection.ReadWrite;
        var allowLazyReserve = !executable &&
            alignedSize >= LargeDataReserveThreshold &&
            alignedSize > FullCommitRegionLimit;
        var reservedOnly = false;

        // Prefer a full commit. Only fall back to reserve-only when a large
        // non-executable commit cannot be satisfied (see TryAllocateAtExact).
        ulong result = 0;
        if (desiredAddress != 0)
        {
            result = TryAllocateFixedThroughGranules(desiredAddress, alignedSize, hostProtection, traceReject: false);
        }

        if (result == 0)
        {
            result = _hostMemory.Allocate(desiredAddress, alignedSize, hostProtection);
        }

        if (result == 0)
        {
            if (!allowAlternative)
            {
                if (allowLazyReserve)
                {
                    result = _hostMemory.Reserve(desiredAddress, alignedSize, HostPageProtection.ReadWrite);
                    reservedOnly = result != 0;
                }

                if (result == 0)
                {
                    throw new InvalidOperationException($"Failed to allocate exact mapping at 0x{desiredAddress:X16} ({alignedSize} bytes)");
                }
            }
            else
            {
                TraceVmem($"Could not allocate at 0x{desiredAddress:X16}, trying any address...");
                result = _hostMemory.Allocate(0, alignedSize, hostProtection);

                if (result == 0 && allowLazyReserve)
                {
                    result = _hostMemory.Reserve(desiredAddress, alignedSize, HostPageProtection.ReadWrite);
                    if (result == 0)
                    {
                        result = _hostMemory.Reserve(0, alignedSize, HostPageProtection.ReadWrite);
                    }

                    reservedOnly = result != 0;
                }

                if (result == 0)
                {
                    throw new OutOfMemoryException($"Failed to allocate {alignedSize} bytes of virtual memory");
                }
            }
        }

        var actualAddress = result;
        var lazyPrimeState = reservedOnly ? PrimeLazyReserveRegion(actualAddress, alignedSize) : "n/a";

        _gate.EnterWriteLock();
        try
        {
            InsertRegionSorted(new MemoryRegion
            {
                VirtualAddress = actualAddress,
                Size = alignedSize,
                IsExecutable = executable,
                IsReservedOnly = reservedOnly,
                Protection = protection
            });
        }
        finally
        {
            _gate.ExitWriteLock();
        }

        var allocationKind = reservedOnly
            ? "reserved data memory (lazy commit)"
            : (executable ? "executable memory" : "data memory");
        TraceVmem($"Allocated {allocationKind}: 0x{actualAddress:X16} - 0x{actualAddress + alignedSize:X16} ({alignedSize} bytes) lazy_prime={lazyPrimeState}");

        return actualAddress;
    }

    /// <summary>
    /// Commits the leading slice of a reserve-only region so early guest touches
    /// succeed before on-demand <see cref="EnsureRangeCommitted"/> runs.
    /// </summary>
    private string PrimeLazyReserveRegion(ulong actualAddress, ulong alignedSize)
    {
        var primeBytes = Math.Min(alignedSize, LazyReservePrimeBytes);
        if (primeBytes == 0)
        {
            return "skip:0";
        }

        ulong committedBytes = 0;
        while (committedBytes < primeBytes)
        {
            var remaining = primeBytes - committedBytes;
            var chunkBytes = Math.Min(remaining, LazyReservePrimeChunkBytes);
            var commitAddress = actualAddress + committedBytes;
            if (!_hostMemory.Commit(commitAddress, chunkBytes, HostPageProtection.ReadWrite))
            {
                break;
            }

            committedBytes += chunkBytes;
        }

        if (committedBytes != 0)
        {
            var state = committedBytes == primeBytes
                ? $"ok:{committedBytes:X}"
                : $"partial:{committedBytes:X}/{primeBytes:X}";
            TraceVmem($"Primed lazy region: 0x{actualAddress:X16} - 0x{actualAddress + committedBytes:X16} ({committedBytes} bytes)");
            return state;
        }

        TraceVmem($"Failed to prime lazy region at 0x{actualAddress:X16} ({primeBytes} bytes), continuing with on-demand commit");
        return $"fail:{primeBytes:X}";
    }

    private ulong TryAllocateFixedThroughGranules(
        ulong desiredAddress,
        ulong alignedSize,
        HostPageProtection hostProtection,
        bool traceReject = true,
        List<ulong>? reservationJournal = null)
    {
        if (!OperatingSystem.IsWindows() || desiredAddress == 0 || alignedSize == 0)
        {
            return 0;
        }

        var requestStart = AlignDown(desiredAddress, PageSize);
        ulong requestEnd;
        ulong granuleEnd;
        try
        {
            requestEnd = AlignUp(desiredAddress + alignedSize, PageSize);
            granuleEnd = AlignUp(requestEnd, HostAllocationGranularity);
        }
        catch (OverflowException)
        {
            return 0;
        }

        var granuleStart = AlignDown(requestStart, HostAllocationGranularity);

        lock (_fixedAllocationGate)
        {
            var newReservations = new List<ulong>();

            void Reject(ulong segmentAddress, string reason)
            {
                if (traceReject)
                {
                    Log.Warn(
                        $"fixed-alloc reject: want=0x{desiredAddress:X16}+0x{alignedSize:X} segment=0x{segmentAddress:X16} {reason}");
                }
                foreach (var reservationBase in newReservations)
                {
                    _hostMemory.Free(reservationBase);
                    _fixedGranuleReservationBases.Remove(reservationBase);
                }
            }

            var cursor = granuleStart;
            while (cursor < granuleEnd)
            {
                if (!_hostMemory.Query(cursor, out var info))
                {
                    Reject(cursor, "query-failed");
                    return 0;
                }

                var segmentEnd = info.RegionSize > ulong.MaxValue - info.BaseAddress
                    ? ulong.MaxValue
                    : info.BaseAddress + info.RegionSize;
                segmentEnd = Math.Min(segmentEnd, granuleEnd);
                if (segmentEnd <= cursor)
                {
                    Reject(cursor, "query-no-progress");
                    return 0;
                }

                if (info.State == HostRegionState.Free)
                {
                    var alignedReserveBase = AlignUp(cursor, HostAllocationGranularity);
                    var unreservableEnd = Math.Min(segmentEnd, alignedReserveBase);
                    if (unreservableEnd > cursor && cursor < requestEnd && unreservableEnd > requestStart)
                    {
                        Reject(cursor, $"free-but-unreservable head (granule base 0x{AlignDown(cursor, HostAllocationGranularity):X16} owned elsewhere)");
                        return 0;
                    }

                    if (alignedReserveBase < segmentEnd)
                    {
                        var reserved = _hostMemory.Reserve(alignedReserveBase, segmentEnd - alignedReserveBase, HostPageProtection.ReadWrite);
                        if (reserved != alignedReserveBase)
                        {
                            if (reserved != 0)
                            {
                                _hostMemory.Free(reserved);
                            }

                            Reject(alignedReserveBase, "reserve-failed");
                            return 0;
                        }

                        _fixedGranuleReservationBases.Add(alignedReserveBase);
                        newReservations.Add(alignedReserveBase);
                    }
                }
                else
                {
                    var trusted = _fixedGranuleReservationBases.Contains(info.AllocationBase) ||
                        IsTrackedRegionBase(info.AllocationBase);
                    if (!trusted && cursor < requestEnd && segmentEnd > requestStart)
                    {
                        Reject(cursor, $"foreign {info.State} allocBase=0x{info.AllocationBase:X16} prot=0x{info.RawProtection:X}");
                        return 0;
                    }
                }

                cursor = segmentEnd;
            }

            var commitCursor = requestStart;
            while (commitCursor < requestEnd)
            {
                if (!_hostMemory.Query(commitCursor, out var info))
                {
                    Reject(commitCursor, "commit-query-failed");
                    return 0;
                }

                var segmentEnd = info.RegionSize > ulong.MaxValue - info.BaseAddress
                    ? ulong.MaxValue
                    : info.BaseAddress + info.RegionSize;
                segmentEnd = Math.Min(segmentEnd, requestEnd);
                if (segmentEnd <= commitCursor)
                {
                    Reject(commitCursor, "commit-no-progress");
                    return 0;
                }

                if (info.State != HostRegionState.Committed &&
                    !_hostMemory.Commit(commitCursor, segmentEnd - commitCursor, hostProtection))
                {
                    Reject(commitCursor, "commit-failed");
                    return 0;
                }

                commitCursor = segmentEnd;
            }

            if (newReservations.Count == 0)
            {
                TraceVmem($"Fixed alloc committed into existing granule reservations: 0x{desiredAddress:X16}+0x{alignedSize:X}");
            }
            else if (reservationJournal is not null)
            {
                // SHARPEMU_FIXED_RANGE_TRANSACTIONAL_ROLLBACK_V1_8_0
                // Publish ownership only after this granule operation has
                // completed successfully. Failed TryAllocateFixedThroughGranules
                // calls free their own local reservations in Reject(), so adding
                // them earlier would make the outer transaction double-free.
                reservationJournal.AddRange(newReservations);
            }

            return desiredAddress;
        }
    }

    private bool IsTrackedRegionBase(ulong allocationBase)
    {
        _gate.EnterReadLock();
        try
        {
            var low = 0;
            var high = _regions.Count - 1;
            while (low <= high)
            {
                var middle = low + ((high - low) >> 1);
                var address = _regions[middle].VirtualAddress;
                if (address == allocationBase)
                {
                    return true;
                }

                if (address < allocationBase)
                {
                    low = middle + 1;
                }
                else
                {
                    high = middle - 1;
                }
            }

            return false;
        }
        finally
        {
            _gate.ExitReadLock();
        }
    }

    public bool TryBackFixedRange(ulong address, ulong size, bool executable)
    {
        // SHARPEMU_FIXED_RANGE_TRANSACTIONAL_ROLLBACK_V1_8_0
        //
        // Fixed backing on Windows uses 64 KiB reservation granules while the
        // guest page size is 4 KiB. Keep the complete multi-run operation under
        // the same re-entrant fixed-allocation gate so a rollback cannot release
        // a reservation another fixed-map thread started using mid-transaction.
        lock (_fixedAllocationGate)
        {
            return TryBackFixedRangeTransactional(address, size, executable);
        }
    }

    private bool TryBackFixedRangeTransactional(ulong address, ulong size, bool executable)
    {
        if (size == 0)
        {
            return false;
        }

        ulong endInput;
        try
        {
            endInput = checked(address + size);
        }
        catch (OverflowException)
        {
            return false;
        }

        var start = AlignDown(address, PageSize);
        var end = AlignUp(endInput, PageSize);
        if (end <= start)
        {
            return false;
        }

        var hostProtection = executable
            ? HostPageProtection.ReadWriteExecute
            : HostPageProtection.ReadWrite;

        // Host allocations are staged and guest MemoryRegions are inserted only
        // after every requested gap has been backed. The granule journal records
        // reservation bases CREATED by successful inner granule operations so a
        // later failure can release exactly those reservations.
        var stagedAllocations =
            new List<(ulong Address, ulong Size, bool GranuleTracked)>();
        var stagedGranuleReservations = new List<ulong>();

        var cursor = start;
        while (cursor < end)
        {
            if (!_hostMemory.Query(cursor, out var info))
            {
                Log.Warn(
                    $"fixed-back reject: want=0x{address:X16}+0x{size:X} " +
                    $"segment=0x{cursor:X16} query-failed");
                goto Rollback;
            }

            var queriedEnd = info.RegionSize > ulong.MaxValue - info.BaseAddress
                ? ulong.MaxValue
                : info.BaseAddress + info.RegionSize;
            var runEnd = Math.Min(end, queriedEnd);
            if (runEnd <= cursor)
            {
                Log.Warn(
                    $"fixed-back reject: want=0x{address:X16}+0x{size:X} " +
                    $"segment=0x{cursor:X16} query-no-progress");
                goto Rollback;
            }

            var runSize = runEnd - cursor;
            var needsGranuleAwareBacking =
                OperatingSystem.IsWindows() &&
                (info.State == HostRegionState.Free ||
                 info.State == HostRegionState.Reserved);

            if (needsGranuleAwareBacking)
            {
                if (TryAllocateFixedThroughGranules(
                        cursor,
                        runSize,
                        hostProtection,
                        traceReject: true,
                        reservationJournal: stagedGranuleReservations) != cursor)
                {
                    goto Rollback;
                }

                stagedAllocations.Add((cursor, runSize, true));
                TraceVmem(
                    $"Backed fixed range gap: 0x{cursor:X16} - " +
                    $"0x{runEnd:X16} ({runSize} bytes)");
            }
            else if (info.State == HostRegionState.Free)
            {
                var allocated =
                    _hostMemory.Allocate(cursor, runSize, hostProtection);

                if (allocated != cursor)
                {
                    if (allocated != 0)
                    {
                        _hostMemory.Free(allocated);
                    }

                    Log.Warn(
                        $"fixed-back reject: want=0x{address:X16}+0x{size:X} " +
                        $"segment=0x{cursor:X16} direct-fixed-allocate-failed");
                    goto Rollback;
                }

                stagedAllocations.Add((cursor, runSize, false));
                TraceVmem(
                    $"Backed fixed range gap: 0x{cursor:X16} - " +
                    $"0x{runEnd:X16} ({runSize} bytes)");
            }
            else
            {
                // Never silently adopt arbitrary host committed pages as guest
                // memory. They are acceptable only when the guest region table
                // already owns the complete occupied run.
                if (!IsAccessible(cursor, runSize))
                {
                    Log.Warn(
                        $"fixed-back reject: want=0x{address:X16}+0x{size:X} " +
                        $"segment=0x{cursor:X16} foreign {info.State} " +
                        $"allocBase=0x{info.AllocationBase:X16} " +
                        $"base=0x{info.BaseAddress:X16} " +
                        $"region=0x{info.RegionSize:X} " +
                        $"prot=0x{info.RawProtection:X}");
                    goto Rollback;
                }

                TraceVmem(
                    $"Fixed range already guest-owned: " +
                    $"0x{cursor:X16}-0x{runEnd:X16}");
            }

            cursor = runEnd;
        }

        if (stagedAllocations.Count == 0)
        {
            // The entire range was already represented by guest MemoryRegions.
            return IsAccessible(start, end - start);
        }

        var protection =
            executable ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE;

        _gate.EnterWriteLock();
        try
        {
            foreach (var (gapAddress, gapSize, _) in stagedAllocations)
            {
                InsertRegionSorted(new MemoryRegion
                {
                    VirtualAddress = gapAddress,
                    Size = gapSize,
                    IsExecutable = executable,
                    IsReservedOnly = false,
                    Protection = protection
                });
            }
        }
        finally
        {
            _gate.ExitWriteLock();
        }

        Interlocked.Increment(ref _mappingGeneration);
        return true;

    Rollback:
        // Direct non-granule allocations are individually owned by this
        // transaction.
        foreach (var (gapAddress, _, granuleTracked) in stagedAllocations)
        {
            if (!granuleTracked)
            {
                _hostMemory.Free(gapAddress);
            }
        }

        // Granule-backed runs may have created 64 KiB reservations in earlier
        // successful inner calls. Those reservations were previously leaked on
        // a later failure, leaving committed host pages with no MemoryRegion and
        // poisoning every retry. The journal contains only reservations created
        // by successful calls in THIS outer transaction.
        if (stagedGranuleReservations.Count != 0)
        {
            var released = new HashSet<ulong>();
            foreach (var reservationBase in stagedGranuleReservations)
            {
                if (!released.Add(reservationBase))
                {
                    continue;
                }

                if (_fixedGranuleReservationBases.Remove(reservationBase))
                {
                    _hostMemory.Free(reservationBase);
                    TraceVmem(
                        $"Rolled back fixed granule reservation: " +
                        $"0x{reservationBase:X16}");
                }
            }
        }

        Log.Warn(
            $"fixed-back transaction rolled back: " +
            $"want=0x{address:X16}+0x{size:X} " +
            $"granules={stagedGranuleReservations.Count} " +
            $"runs={stagedAllocations.Count}");

        return false;
    }

    public bool TryAllocateAtOrAbove(
        ulong desiredAddress,
        ulong size,
        bool executable,
        ulong alignment,
        out ulong actualAddress)
    {
        actualAddress = 0;
        if (size == 0)
        {
            return false;
        }

        var alignedSize = AlignUp(size, PageSize);
        var effectiveAlignment = Math.Max(PageSize, alignment == 0 ? PageSize : alignment);
        var requestedCursor = AlignUp(desiredAddress, effectiveAlignment);
        var cursor = GetAllocationSearchCursor(desiredAddress, requestedCursor, effectiveAlignment, executable);

        // macOS needs alignment over-allocation; Linux uses exact-address search.
        if (OperatingSystem.IsMacOS())
        {
            var reserveSize = effectiveAlignment > PageSize
                ? alignedSize + effectiveAlignment
                : alignedSize;
            try
            {
                var posixAddress = AllocateAt(cursor, reserveSize, executable, allowAlternative: true);
                if (posixAddress != 0)
                {
                    var alignedBase = AlignUp(posixAddress, effectiveAlignment);
                    if (alignedBase + alignedSize <= posixAddress + reserveSize)
                    {
                        actualAddress = alignedBase;
                        UpdateAllocationSearchCursor(desiredAddress, effectiveAlignment, executable, alignedBase + alignedSize);
                        return true;
                    }

                    ReleaseUntrackedAllocation(posixAddress);
                }
            }
            catch
            {
            }

            return false;
        }

        for (var attempt = 0; attempt < 0x10000; attempt++)
        {
            if (cursor == 0 || ulong.MaxValue - cursor < alignedSize)
            {
                return false;
            }

            if (TryGetOverlappingRegionEnd(cursor, alignedSize, out var overlapEnd))
            {
                cursor = AlignUp(overlapEnd, effectiveAlignment);
                continue;
            }

            if (TryAllocateAtExact(cursor, alignedSize, executable, out actualAddress))
            {
                UpdateAllocationSearchCursor(desiredAddress, effectiveAlignment, executable, actualAddress + alignedSize);
                return true;
            }

            cursor = AlignUp(cursor + effectiveAlignment, effectiveAlignment);
        }

        return false;
    }

    private void ReleaseUntrackedAllocation(ulong address)
    {
        _gate.EnterWriteLock();
        try
        {
            for (var i = 0; i < _regions.Count; i++)
            {
                if (_regions[i].VirtualAddress == address)
                {
                    _regions.RemoveAt(i);
                    break;
                }
            }
        }
        finally
        {
            _gate.ExitWriteLock();
        }

        Interlocked.Increment(ref _mappingGeneration);
        _hostMemory.Free(address);
    }

    public bool TryAllocateGuestMemory(ulong size, ulong alignment, out ulong address)
    {
        address = 0;
        if (size == 0 || alignment == 0 || (alignment & (alignment - 1)) != 0)
        {
            return false;
        }

        lock (_guestAllocationGate)
        {
            if (_guestAllocationArenaBase == 0)
            {
                try
                {
                    _guestAllocationArenaBase = AllocateAt(
                        GuestAllocationArenaAddress,
                        GuestAllocationArenaSize,
                        executable: false,
                        allowAlternative: true);
                    _guestAllocationFreeRanges.Add(
                        GuestAllocationArenaStartOffset,
                        GuestAllocationArenaSize - GuestAllocationArenaStartOffset);
                }
                catch (Exception)
                {
                    return false;
                }
            }

            ulong rangeOffset = 0;
            ulong rangeSize = 0;
            ulong alignedOffset = 0;
            var found = false;
            foreach (var range in _guestAllocationFreeRanges)
            {
                alignedOffset = AlignUp(range.Key, alignment);
                if (alignedOffset >= range.Key &&
                    alignedOffset - range.Key <= range.Value &&
                    size <= range.Value - (alignedOffset - range.Key))
                {
                    rangeOffset = range.Key;
                    rangeSize = range.Value;
                    found = true;
                    break;
                }
            }

            if (!found)
            {
                return false;
            }

            _guestAllocationFreeRanges.Remove(rangeOffset);
            if (alignedOffset > rangeOffset)
            {
                _guestAllocationFreeRanges.Add(rangeOffset, alignedOffset - rangeOffset);
            }

            var allocationEnd = alignedOffset + size;
            var rangeEnd = rangeOffset + rangeSize;
            if (allocationEnd < rangeEnd)
            {
                _guestAllocationFreeRanges.Add(allocationEnd, rangeEnd - allocationEnd);
            }

            address = _guestAllocationArenaBase + alignedOffset;
            _guestAllocations.Add(address, (alignedOffset, size));
            return true;
        }
    }

    public bool TryFreeGuestMemory(ulong address)
    {
        lock (_guestAllocationGate)
        {
            if (!_guestAllocations.Remove(address, out var allocation))
            {
                return false;
            }

            var freeOffset = allocation.Offset;
            var freeSize = allocation.Size;
            ulong? previousOffset = null;
            ulong? nextOffset = null;

            foreach (var range in _guestAllocationFreeRanges)
            {
                if (range.Key < freeOffset)
                {
                    previousOffset = range.Key;
                    continue;
                }

                nextOffset = range.Key;
                break;
            }

            if (previousOffset is { } previous &&
                previous + _guestAllocationFreeRanges[previous] == freeOffset)
            {
                freeOffset = previous;
                freeSize += _guestAllocationFreeRanges[previous];
                _guestAllocationFreeRanges.Remove(previous);
            }

            if (nextOffset is { } next && freeOffset + freeSize == next)
            {
                freeSize += _guestAllocationFreeRanges[next];
                _guestAllocationFreeRanges.Remove(next);
            }

            _guestAllocationFreeRanges.Add(freeOffset, freeSize);
            return true;
        }
    }

    public bool TryProtect(ulong address, ulong size, GuestPageProtection protection)
    {
        if (size == 0)
        {
            return false;
        }

        var protectedOkV91 = _hostMemory.Protect(
            address,
            size,
            ResolveProtection(protection),
            out _);
        if (protectedOkV91)
        {
            Interlocked.Increment(ref _protectionGenerationV91);
        }

        return protectedOkV91;
    }

    // Reproduces the decomposition KernelMemoryCompatExports.ResolveHostProtection
    // performed before this seam existed; the Windows backend maps each case back
    // to the identical PAGE_* value.
    private static HostPageProtection ResolveProtection(GuestPageProtection protection)
    {
        var read = (protection & GuestPageProtection.Read) != 0;
        var write = (protection & GuestPageProtection.Write) != 0;
        var execute = (protection & GuestPageProtection.Execute) != 0;

        if (execute)
        {
            return write
                ? HostPageProtection.ReadWriteExecute
                : read
                    ? HostPageProtection.ReadExecute
                    : HostPageProtection.Execute;
        }

        return write
            ? HostPageProtection.ReadWrite
            : read
                ? HostPageProtection.ReadOnly
                : HostPageProtection.NoAccess;
    }

    public void Clear()
    {
        lock (_guestAllocationGate)
        {
            lock (_fixedAllocationGate)
            {
                _gate.EnterWriteLock();
                try
                {
                    var freedBases = new HashSet<ulong>();
                    foreach (var region in _regions)
                    {
                        if (freedBases.Add(region.VirtualAddress))
                        {
                            _hostMemory.Free(region.VirtualAddress);
                        }
                    }

                    foreach (var reservationBase in _fixedGranuleReservationBases)
                    {
                        if (freedBases.Add(reservationBase))
                        {
                            _hostMemory.Free(reservationBase);
                        }
                    }

                    _fixedGranuleReservationBases.Clear();
                    _regions.Clear();
                    _pageProtections.Clear();
                    lock (_allocationSearchHintGate)
                    {
                        _allocationSearchHints.Clear();
                    }
                    Interlocked.Increment(ref _mappingGeneration);
                }
                finally
                {
                    _gate.ExitWriteLock();
                }
            }

            _guestAllocationArenaBase = 0;
            _guestAllocationFreeRanges.Clear();
            _guestAllocations.Clear();
        }
    }

    public void Map(ulong virtualAddress, ulong memorySize, ulong fileOffset, ReadOnlySpan<byte> fileData, ProgramHeaderFlags protection)
    {
        MapCore(
            virtualAddress,
            memorySize,
            fileOffset,
            fileData,
            protection,
            deferFinalProtection: false,
            preserveDemandZeroPages: false);
    }

    // SHARPEMU_V74_0_56_32_LOADER_STAGED_MAPPING
    //
    // ELF/SELF relocations are loader writes. Mapping PT_LOAD with its final
    // RX/R protections before relocations forces every relocation targeting a
    // non-writable page through VirtualProtect/restore (and potentially an
    // instruction-cache flush). Keep loader segments writable until the image
    // has been fully relocated, then apply the guest-visible final protections
    // in one pass from SelfLoader.
    public void MapLoaderSegment(
        ulong virtualAddress,
        ulong memorySize,
        ulong fileOffset,
        ReadOnlySpan<byte> fileData,
        ProgramHeaderFlags protection)
    {
        MapCore(
            virtualAddress,
            memorySize,
            fileOffset,
            fileData,
            protection,
            deferFinalProtection: true,
            preserveDemandZeroPages: true);
    }

    public void FinalizeLoaderSegmentProtection(
        ulong virtualAddress,
        ulong memorySize,
        ProgramHeaderFlags protection)
    {
        if (memorySize == 0)
        {
            return;
        }

        var mapStart = AlignDown(virtualAddress, PageSize);
        var mapEnd = AlignUp(checked(virtualAddress + memorySize), PageSize);

        _gate.EnterWriteLock();
        try
        {
            ApplySegmentProtection(mapStart, mapEnd, protection);
        }
        finally
        {
            _gate.ExitWriteLock();
        }
    }

    private void MapCore(
        ulong virtualAddress,
        ulong memorySize,
        ulong fileOffset,
        ReadOnlySpan<byte> fileData,
        ProgramHeaderFlags protection,
        bool deferFinalProtection,
        bool preserveDemandZeroPages)
    {
        if (memorySize == 0)
            throw new ArgumentOutOfRangeException(nameof(memorySize));

        if ((ulong)fileData.Length > memorySize)
            throw new ArgumentOutOfRangeException(nameof(fileData), "File size cannot exceed memory size");

        var mapStart = AlignDown(virtualAddress, PageSize);
        var segmentEnd = checked(virtualAddress + memorySize);
        var mapEnd = AlignUp(segmentEnd, PageSize);
        var mapSize = checked(mapEnd - mapStart);

        _gate.EnterWriteLock();
        try
        {
            var existingRegion = FindRegion(mapStart, mapSize);
            var sparseParent = existingRegion is { IsReservedOnly: true };
            List<(ulong Start, ulong End)>? committedZeroRanges = null;

            if (existingRegion == null)
            {
                var isExecutable = (protection & ProgramHeaderFlags.Execute) != 0;
                AllocateAt(mapStart, mapSize, isExecutable, allowAlternative: false);
                existingRegion = FindRegion(mapStart, mapSize);
            }
            else if (sparseParent)
            {
                if (preserveDemandZeroPages)
                {
                    var zeroStart = checked(virtualAddress + (ulong)fileData.Length);
                    var zeroSize = memorySize - (ulong)fileData.Length;
                    committedZeroRanges = CaptureCommittedRanges(zeroStart, zeroSize);
                }

                if (!EnsureRangeCommitted(mapStart, mapSize, existingRegion))
                {
                    throw new InvalidOperationException(
                        $"Failed to commit loader segment at 0x{mapStart:X16} (size=0x{mapSize:X}).");
                }
            }

            var stageProtection = (protection & ProgramHeaderFlags.Execute) != 0
                ? ProgramHeaderFlags.Read | ProgramHeaderFlags.Write | ProgramHeaderFlags.Execute
                : ProgramHeaderFlags.Read | ProgramHeaderFlags.Write;
            SetProtection(mapStart, mapSize, stageProtection);

            if (!fileData.IsEmpty)
            {
                var destPtr = (void*)virtualAddress;
                fixed (byte* srcPtr = fileData)
                {
                    Buffer.MemoryCopy(srcPtr, destPtr, (nuint)memorySize, (nuint)fileData.Length);
                }
            }

            var zeroFillSize = memorySize - (ulong)fileData.Length;
            if (zeroFillSize != 0)
            {
                var zeroStart = checked(virtualAddress + (ulong)fileData.Length);
                if (sparseParent && preserveDemandZeroPages)
                {
                    // MEM_COMMIT pages are demand-zero. Do not touch every BSS
                    // page just to write zeros the OS already guarantees. Only
                    // clear subranges that were committed before this segment
                    // (typically a shared/overlapping boundary page).
                    ClearCommittedRanges(
                        zeroStart,
                        checked(zeroStart + zeroFillSize),
                        committedZeroRanges);
                }
                else
                {
                    NativeMemory.Clear((void*)zeroStart, (nuint)zeroFillSize);
                }
            }

            if (!deferFinalProtection)
            {
                ApplySegmentProtection(mapStart, mapEnd, protection);
            }

            TraceVmem(
                $"Mapped segment: 0x{virtualAddress:X16} - 0x{virtualAddress + memorySize:X16} " +
                $"(file: {fileData.Length} bytes, prot: {protection}, staged={deferFinalProtection}, sparse={sparseParent})");
        }
        finally
        {
            _gate.ExitWriteLock();
        }
    }

    private List<(ulong Start, ulong End)>? CaptureCommittedRanges(ulong address, ulong size)
    {
        if (size == 0)
        {
            return null;
        }

        var end = checked(address + size);
        var cursor = address;
        List<(ulong Start, ulong End)>? ranges = null;

        while (cursor < end)
        {
            if (!_hostMemory.Query(cursor, out var info))
            {
                break;
            }

            var infoEnd = info.RegionSize > ulong.MaxValue - info.BaseAddress
                ? ulong.MaxValue
                : info.BaseAddress + info.RegionSize;
            var rangeEnd = Math.Min(end, infoEnd);
            if (rangeEnd <= cursor)
            {
                break;
            }

            if (info.State == HostRegionState.Committed)
            {
                (ranges ??= new List<(ulong Start, ulong End)>())
                    .Add((cursor, rangeEnd));
            }

            cursor = rangeEnd;
        }

        return ranges;
    }

    private static void ClearCommittedRanges(
        ulong zeroStart,
        ulong zeroEnd,
        List<(ulong Start, ulong End)>? committedRanges)
    {
        if (committedRanges is null)
        {
            return;
        }

        foreach (var range in committedRanges)
        {
            var start = Math.Max(zeroStart, range.Start);
            var end = Math.Min(zeroEnd, range.End);
            if (end > start)
            {
                NativeMemory.Clear((void*)start, (nuint)(end - start));
            }
        }
    }

    private void ApplySegmentProtection(ulong mapStart, ulong mapEnd, ProgramHeaderFlags flags)
    {
        var runStart = mapStart;
        var runFlags = ProgramHeaderFlags.None;
        var hasRun = false;

        for (var pageAddress = mapStart; pageAddress < mapEnd; pageAddress += PageSize)
        {
            _pageProtections.TryGetValue(pageAddress, out var existingFlags);
            var mergedFlags = existingFlags | flags;
            _pageProtections[pageAddress] = mergedFlags;

            if (!hasRun)
            {
                runStart = pageAddress;
                runFlags = mergedFlags;
                hasRun = true;
            }
            else if (mergedFlags != runFlags)
            {
                SetProtection(runStart, pageAddress - runStart, runFlags);
                runStart = pageAddress;
                runFlags = mergedFlags;
            }
        }

        if (hasRun)
        {
            SetProtection(runStart, mapEnd - runStart, runFlags);
            Interlocked.Increment(ref _protectionGenerationV91);
        }
    }

    private void SetProtection(ulong address, ulong size, ProgramHeaderFlags flags)
    {
        HostPageProtection protection;

        if (flags == ProgramHeaderFlags.None)
        {
            protection = HostPageProtection.NoAccess;
        }
        else if ((flags & ProgramHeaderFlags.Execute) != 0)
        {
            protection = (flags & ProgramHeaderFlags.Write) != 0
                ? HostPageProtection.ReadWriteExecute
                : HostPageProtection.ReadExecute;
        }
        else if ((flags & ProgramHeaderFlags.Write) != 0)
        {
            protection = HostPageProtection.ReadWrite;
        }
        else
        {
            protection = HostPageProtection.ReadOnly;
        }

        if (!_hostMemory.Protect(address, size, protection, out _))
        {
            throw new InvalidOperationException($"Failed to set memory protection at 0x{address:X16}");
        }

        if ((flags & ProgramHeaderFlags.Execute) != 0)
        {
            _hostMemory.FlushInstructionCache(address, size);
        }
    }

    public IReadOnlyList<VirtualMemoryRegion> SnapshotRegions()
    {
        _gate.EnterReadLock();
        try
        {
            var snapshot = new VirtualMemoryRegion[_regions.Count];
            for (var i = 0; i < _regions.Count; i++)
            {
                var r = _regions[i];
                snapshot[i] = new VirtualMemoryRegion(
                    r.VirtualAddress,
                    r.Size,
                    0,
                    r.Size,
                    r.IsExecutable ? ProgramHeaderFlags.Execute | ProgramHeaderFlags.Read : ProgramHeaderFlags.Read);
            }
            return snapshot;
        }
        finally
        {
            _gate.ExitReadLock();
        }
    }

    public bool TryRead(ulong virtualAddress, Span<byte> destination)
    {
        var requiresExclusiveAccess = false;
        var useLargeReadCacheV11711 =
            _shaderLargeReadAccessCacheV11711 &&
            destination.Length >= ShaderLargeReadMinimumBytesV11711;
        LargeReadAccessCacheV11711? largeReadCacheV11711 = null;
        var largeReadSlotV11711 = -1;
        var largeReadAccessCoveredV11711 = false;
        var largeReadTraceCountV11711 = 0L;

        if (useLargeReadCacheV11711)
        {
            largeReadTraceCountV11711 =
                Interlocked.Increment(ref V11711LargeReadCalls);
            Interlocked.Add(ref V11711RequestedBytes, destination.Length);
        }

        _gate.EnterReadLock();
        try
        {
            MemoryRegion? region;
            ulong offset;
            if (useLargeReadCacheV11711)
            {
                if (!TryResolveLargeReadRegionV11711(
                        virtualAddress,
                        (ulong)destination.Length,
                        out region,
                        out offset,
                        out largeReadCacheV11711,
                        out largeReadSlotV11711,
                        out largeReadAccessCoveredV11711))
                {
                    TraceLargeReadCacheV11711(largeReadTraceCountV11711);
                    return false;
                }
            }
            else
            {
                region = FindRegion(
                    virtualAddress,
                    (ulong)destination.Length);
                if (region is null ||
                    !TryResolveRegionOffset(
                        virtualAddress,
                        (ulong)destination.Length,
                        region,
                        out offset))
                {
                    return false;
                }
            }

            var srcPtr = (void*)(region.VirtualAddress + offset);
            if (destination.IsEmpty)
            {
                return true;
            }

            if (region.IsReservedOnly &&
                !EnsureRangeCommitted(
                    (ulong)srcPtr,
                    (ulong)destination.Length,
                    region))
            {
                TraceLargeReadCacheV11711(largeReadTraceCountV11711);
                return false;
            }

            var readableWithoutProtectionChangeV11711 =
                largeReadAccessCoveredV11711;
            if (!readableWithoutProtectionChangeV11711)
            {
                if (useLargeReadCacheV11711)
                {
                    Interlocked.Increment(ref V11711AccessMisses);
                }

                readableWithoutProtectionChangeV11711 =
                    CanReadWithoutProtectionChange(
                        (ulong)srcPtr,
                        (ulong)destination.Length,
                        region);
                if (readableWithoutProtectionChangeV11711 &&
                    useLargeReadCacheV11711 &&
                    largeReadCacheV11711 is not null &&
                    largeReadSlotV11711 >= 0)
                {
                    RememberLargeReadAccessV11711(
                        largeReadCacheV11711,
                        largeReadSlotV11711,
                        region,
                        (ulong)srcPtr,
                        (ulong)destination.Length);
                }
            }

            if (!readableWithoutProtectionChangeV11711)
            {
                requiresExclusiveAccess = true;
            }
            else
            {
                fixed (byte* destPtr = destination)
                {
                    // Always copy current live guest bytes. V117.11 only caches
                    // region/protection validation, never buffer contents.
                    Buffer.MemoryCopy(
                        srcPtr,
                        destPtr,
                        (nuint)destination.Length,
                        (nuint)destination.Length);
                }

                if (useLargeReadCacheV11711)
                {
                    Interlocked.Increment(ref V11711LiveCopies);
                    TraceLargeReadCacheV11711(largeReadTraceCountV11711);
                }

                return true;
            }
        }
        finally
        {
            _gate.ExitReadLock();
        }

        if (!requiresExclusiveAccess)
        {
            TraceLargeReadCacheV11711(largeReadTraceCountV11711);
            return false;
        }

        _gate.EnterWriteLock();
        try
        {
            var resultV11711 =
                TryReadExclusive(virtualAddress, destination);
            TraceLargeReadCacheV11711(largeReadTraceCountV11711);
            return resultV11711;
        }
        finally
        {
            _gate.ExitWriteLock();
        }
    }

    private static int GetLargeReadCacheSlotV11711(ulong address)
    {
        var page = address >> 12;
        var mixed = page ^ (page >> 7) ^ (page >> 17);
        return (int)(mixed & (ShaderLargeReadCacheSlotsV11711 - 1));
    }

    private bool TryResolveLargeReadRegionV11711(
        ulong address,
        ulong size,
        out MemoryRegion region,
        out ulong offset,
        out LargeReadAccessCacheV11711 cache,
        out int slot,
        out bool accessCovered)
    {
        region = null!;
        offset = 0;
        accessCovered = false;

        var mappingGenerationV11711 =
            Volatile.Read(ref _mappingGeneration);
        var protectionGenerationV11711 =
            Volatile.Read(ref _protectionGenerationV91);
        cache = _largeReadAccessCacheV11711 ??=
            new LargeReadAccessCacheV11711();
        if (!ReferenceEquals(cache.Owner, this) ||
            cache.MappingGeneration != mappingGenerationV11711 ||
            cache.ProtectionGeneration != protectionGenerationV11711)
        {
            cache.Reset(
                this,
                mappingGenerationV11711,
                protectionGenerationV11711);
        }

        slot = GetLargeReadCacheSlotV11711(address);
        var cachedRegionV11711 = cache.Regions[slot];

        // Resolve region by address only. This keeps the successful lookup
        // across the evaluator's 16MiB -> ... -> 4KiB extent probe ladder.
        if (cachedRegionV11711 is not null &&
            TryResolveRegionOffset(
                address,
                1,
                cachedRegionV11711,
                out _))
        {
            region = cachedRegionV11711;
            Interlocked.Increment(ref V11711RegionHits);
        }
        else
        {
            cachedRegionV11711 = FindRegion(address, 1);
            if (cachedRegionV11711 is null)
            {
                Interlocked.Increment(ref V11711RegionMisses);
                return false;
            }

            region = cachedRegionV11711;
            cache.Regions[slot] = region;
            cache.ReadStartPages[slot] = 0;
            cache.ReadEndPages[slot] = 0;
            Interlocked.Increment(ref V11711RegionMisses);
        }

        if (!TryResolveRegionOffset(
                address,
                size,
                region,
                out offset))
        {
            Interlocked.Increment(ref V11711ExtentRejects);
            return false;
        }

        var startPageV11711 = AlignDown(address, PageSize);
        var endPageV11711 = AlignUp(address + size, PageSize);
        if (cache.ReadEndPages[slot] > cache.ReadStartPages[slot] &&
            startPageV11711 >= cache.ReadStartPages[slot] &&
            endPageV11711 <= cache.ReadEndPages[slot])
        {
            accessCovered = true;
            Interlocked.Increment(ref V11711AccessHits);
            Interlocked.Add(
                ref V11711PagesBypassed,
                checked((long)(
                    (endPageV11711 - startPageV11711) / PageSize)));
        }

        return true;
    }

    private static void RememberLargeReadAccessV11711(
        LargeReadAccessCacheV11711 cache,
        int slot,
        MemoryRegion region,
        ulong address,
        ulong size)
    {
        cache.Regions[slot] = region;
        cache.ReadStartPages[slot] =
            AlignDown(address, PageSize);
        cache.ReadEndPages[slot] =
            AlignUp(address + size, PageSize);
    }

    private static void TraceLargeReadCacheV11711(long count)
    {
        if (count <= 0 ||
            (count > 16 && (count & (count - 1)) != 0))
        {
            return;
        }

        Console.Error.WriteLine(
            "[V74.0.117.11][PVM_SHADER_READ_CACHE] " +
            $"reads={Volatile.Read(ref V11711LargeReadCalls)} " +
            $"region_hit={Volatile.Read(ref V11711RegionHits)} " +
            $"region_miss={Volatile.Read(ref V11711RegionMisses)} " +
            $"extent_reject={Volatile.Read(ref V11711ExtentRejects)} " +
            $"access_hit={Volatile.Read(ref V11711AccessHits)} " +
            $"access_miss={Volatile.Read(ref V11711AccessMisses)} " +
            $"live_copy={Volatile.Read(ref V11711LiveCopies)} " +
            $"bytes={Volatile.Read(ref V11711RequestedBytes)} " +
            $"pages_bypassed={Volatile.Read(ref V11711PagesBypassed)}");
    }

    public bool TryCompare(ulong virtualAddress, ReadOnlySpan<byte> expected)
    {
        _gate.EnterReadLock();
        try
        {
            var region = FindRegion(virtualAddress, (ulong)expected.Length);
            if (region is null ||
                !TryResolveRegionOffset(
                    virtualAddress,
                    (ulong)expected.Length,
                    region,
                    out var offset))
            {
                return false;
            }

            if (expected.IsEmpty)
            {
                return true;
            }

            var srcPtr = (void*)(region.VirtualAddress + offset);
            if (region.IsReservedOnly &&
                !EnsureRangeCommitted((ulong)srcPtr, (ulong)expected.Length, region))
            {
                return false;
            }

            if (!CanReadWithoutProtectionChange((ulong)srcPtr, (ulong)expected.Length, region))
            {
                return false;
            }

            return new ReadOnlySpan<byte>(srcPtr, expected.Length).SequenceEqual(expected);
        }
        finally
        {
            _gate.ExitReadLock();
        }
    }

    public bool TryWrite(ulong virtualAddress, ReadOnlySpan<byte> source)
    {
        // A managed write into a page the guest-image write tracker has
        // protected surfaces as a fatal AccessViolation — the runtime turns
        // SIGSEGV in managed code into an exception before the resumable
        // signal bridge can restore access (native guest stores recover
        // there). Pre-visit the span so tracked pages are unprotected and
        // their owners dirtied before the copy; guest addresses are
        // host-identical, matching the tracker's fault addresses.
        GuestImageWriteTracker.NotifyManagedWrite(virtualAddress, (ulong)source.Length);

        var requiresExclusiveAccess = false;
        _gate.EnterReadLock();
        try
        {
            var region = FindRegion(virtualAddress, (ulong)source.Length);
            if (region is not null &&
                TryResolveRegionOffset(
                    virtualAddress,
                    (ulong)source.Length,
                    region,
                    out var offset))
            {
                var destPtr = (void*)(region.VirtualAddress + offset);
                if (source.IsEmpty)
                {
                    return true;
                }

                if (region.IsReservedOnly)
                {
                    if (!EnsureRangeCommitted((ulong)destPtr, (ulong)source.Length, region))
                    {
                        return false;
                    }
                }

                if (!CanWriteWithoutProtectionChange((ulong)destPtr, (ulong)source.Length, region))
                {
                    requiresExclusiveAccess = true;
                }
                else
                {
                    fixed (byte* srcPtr = source)
                    {
                        Buffer.MemoryCopy(srcPtr, destPtr, (nuint)source.Length, (nuint)source.Length);
                    }

                    NotifyGuestWriteWatch(virtualAddress, source);
                    return true;
                }
            }
        }
        finally
        {
            _gate.ExitReadLock();
        }

        if (!requiresExclusiveAccess)
        {
            return false;
        }

        _gate.EnterWriteLock();
        try
        {
            return TryWriteExclusive(virtualAddress, source);
        }
        finally
        {
            _gate.ExitWriteLock();
        }
    }

    private static void NotifyGuestWriteWatch(ulong virtualAddress, ReadOnlySpan<byte> source)
    {
        if (GuestWriteWatch.Armed)
        {
            GuestWriteWatch.Check(virtualAddress, source);
        }
    }

    /// <summary>
    /// Allocation-free repeating-pattern write for semantic GPU operations.
    /// This is deliberately implemented at the physical guest-memory layer so
    /// large fills do not create a same-sized managed array on every dispatch.
    /// </summary>
    public bool TryFillPattern(ulong virtualAddress, ReadOnlySpan<byte> pattern, ulong length)
    {
        if (length == 0)
        {
            return true;
        }
        if (pattern.IsEmpty || length > int.MaxValue)
        {
            return false;
        }

        GuestImageWriteTracker.NotifyManagedWrite(virtualAddress, length);

        var requiresExclusiveAccess = false;
        _gate.EnterReadLock();
        try
        {
            var region = FindRegion(virtualAddress, length);
            if (region is not null &&
                TryResolveRegionOffset(virtualAddress, length, region, out var offset))
            {
                var destinationPointer = region.VirtualAddress + offset;
                if (region.IsReservedOnly &&
                    !EnsureRangeCommitted(destinationPointer, length, region))
                {
                    return false;
                }

                if (!CanWriteWithoutProtectionChange(destinationPointer, length, region))
                {
                    requiresExclusiveAccess = true;
                }
                else
                {
                    var destination = new Span<byte>((void*)destinationPointer, checked((int)length));
                    FillPattern(destination, pattern);
                    NotifyGuestWriteWatch(virtualAddress, destination);
                    return true;
                }
            }
        }
        finally
        {
            _gate.ExitReadLock();
        }

        if (!requiresExclusiveAccess)
        {
            return false;
        }

        _gate.EnterWriteLock();
        try
        {
            return TryFillPatternExclusive(virtualAddress, pattern, length);
        }
        finally
        {
            _gate.ExitWriteLock();
        }
    }

    private static void FillPattern(Span<byte> destination, ReadOnlySpan<byte> pattern)
    {
        var filled = Math.Min(pattern.Length, destination.Length);
        pattern[..filled].CopyTo(destination);
        while (filled < destination.Length)
        {
            var copyLength = Math.Min(filled, destination.Length - filled);
            destination[..copyLength].CopyTo(destination.Slice(filled, copyLength));
            filled += copyLength;
        }
    }

    public bool TryCopy(ulong destinationAddress, ulong sourceAddress, ulong length)
    {
        if (length == 0 || destinationAddress == sourceAddress)
        {
            return true;
        }
        if (length > int.MaxValue)
        {
            return false;
        }

        // Match TryWrite's managed-write notification before touching an
        // identity-mapped guest page protected by the image tracker.
        GuestImageWriteTracker.NotifyManagedWrite(destinationAddress, length);

        _gate.EnterReadLock();
        try
        {
            if (!TryResolveCopyRegionPairV1840(
                    sourceAddress,
                    destinationAddress,
                    length,
                    out var sourceRegion,
                    out var sourceOffset,
                    out var destinationRegion,
                    out var destinationOffset))
            {
                return false;
            }

            var sourcePointer = sourceRegion.VirtualAddress + sourceOffset;
            var destinationPointer = destinationRegion.VirtualAddress + destinationOffset;

            // SHARPEMU_V74_0_91_2_MEMCPY_PROTECTION_CACHE
            // Preserve whichever region resolver owns the checkout (legacy or
            // DBFZ V1.8.40 CopyRegionPairCache) and cache only the expensive
            // page-permission checks. Mapping/protection generations invalidate
            // the cache while the existing VM read lock keeps region lifetime safe.
            var mappingGenerationV912 = Volatile.Read(ref _mappingGeneration);
            var protectionGenerationV912 = Volatile.Read(ref _protectionGenerationV91);
            var accessCacheV912 = _copyRegionAccessCacheV91 ??= new CopyRegionAccessCacheV91();
            if (!ReferenceEquals(accessCacheV912.Owner, this) ||
                accessCacheV912.MappingGeneration != mappingGenerationV912 ||
                accessCacheV912.ProtectionGeneration != protectionGenerationV912)
            {
                accessCacheV912.Reset(this, mappingGenerationV912, protectionGenerationV912);
            }
            if ((sourceRegion.IsReservedOnly &&
                 !EnsureRangeCommitted(sourcePointer, length, sourceRegion)) ||
                (destinationRegion.IsReservedOnly &&
                 !EnsureRangeCommitted(destinationPointer, length, destinationRegion)) ||
                !CanAccessWithoutProtectionChangeCachedV91(
                    accessCacheV912, sourcePointer, length, sourceRegion, write: false) ||
                !CanAccessWithoutProtectionChangeCachedV91(
                    accessCacheV912, destinationPointer, length, destinationRegion, write: true))
            {
                return false;
            }

            // Span.CopyTo has memmove overlap semantics, so this allocation-free
            // path safely serves both libc memcpy and libc memmove.
            new ReadOnlySpan<byte>((void*)sourcePointer, checked((int)length)).CopyTo(
                new Span<byte>((void*)destinationPointer, checked((int)length)));
            NotifyGuestWriteWatch(
                destinationAddress,
                new ReadOnlySpan<byte>((void*)destinationPointer, checked((int)length)));
            // SHARPEMU_V74_0_117_8_GUEST_MEMORY_PROVENANCE_PROPAGATION
            // PhysicalVirtualMemory is the shared fast path for HLE/native libc
            // memcpy/memmove. Metadata propagation occurs only after the bytes
            // were copied successfully and never changes memory semantics.
            GuestResourceProvenance.PropagateCopy(
                sourceAddress,
                destinationAddress,
                length,
                "physical-vmem-copy");
            return true;
        }
        finally
        {
            _gate.ExitReadLock();
        }
    }

    private bool CanAccessWithoutProtectionChangeCachedV91(
        CopyRegionAccessCacheV91 cache,
        ulong address,
        ulong size,
        MemoryRegion region,
        bool write)
    {
        var startPage = AlignDown(address, PageSize);
        var endPage = AlignUp(address + size, PageSize);
        if (write)
        {
            if (ReferenceEquals(cache.WriteAccessRegion, region) &&
                startPage >= cache.WriteAccessStartPage &&
                endPage <= cache.WriteAccessEndPage)
            {
                return true;
            }
        }
        else if (ReferenceEquals(cache.ReadAccessRegion, region) &&
                 startPage >= cache.ReadAccessStartPage &&
                 endPage <= cache.ReadAccessEndPage)
        {
            return true;
        }

        if (!CanAccessWithoutProtectionChange(address, size, region, write))
        {
            return false;
        }

        if (write)
        {
            cache.WriteAccessRegion = region;
            cache.WriteAccessStartPage = startPage;
            cache.WriteAccessEndPage = endPage;
        }
        else
        {
            cache.ReadAccessRegion = region;
            cache.ReadAccessStartPage = startPage;
            cache.ReadAccessEndPage = endPage;
        }

        return true;
    }

    private bool TryReadExclusive(ulong virtualAddress, Span<byte> destination)
    {
        var region = FindRegion(virtualAddress, (ulong)destination.Length);
        if (region is not null &&
            TryResolveRegionOffset(
                virtualAddress,
                (ulong)destination.Length,
                region,
                out var offset))
        {
            var srcPtr = (void*)(region.VirtualAddress + offset);
            if (!EnsureRangeCommitted((ulong)srcPtr, (ulong)destination.Length, region))
            {
                return false;
            }

            if (CanReadWithoutProtectionChange((ulong)srcPtr, (ulong)destination.Length, region))
            {
                fixed (byte* destPtr = destination)
                {
                    Buffer.MemoryCopy(srcPtr, destPtr, (nuint)destination.Length, (nuint)destination.Length);
                }

                return true;
            }

            if (!TryTemporarilyProtectForRead((ulong)srcPtr, (ulong)destination.Length, region, out var touchedPages))
            {
                return false;
            }

            try
            {
                fixed (byte* destPtr = destination)
                {
                    Buffer.MemoryCopy(srcPtr, destPtr, (nuint)destination.Length, (nuint)destination.Length);
                }
            }
            finally
            {
                RestorePageProtections(touchedPages);
            }

            return true;
        }

        return false;
    }

    private bool TryWriteExclusive(ulong virtualAddress, ReadOnlySpan<byte> source)
    {
        var region = FindRegion(virtualAddress, (ulong)source.Length);
        if (region is not null &&
            TryResolveRegionOffset(
                virtualAddress,
                (ulong)source.Length,
                region,
                out var offset))
        {
            var destPtr = (void*)(region.VirtualAddress + offset);
            if (!EnsureRangeCommitted((ulong)destPtr, (ulong)source.Length, region))
            {
                return false;
            }

            if (CanWriteWithoutProtectionChange((ulong)destPtr, (ulong)source.Length, region))
            {
                fixed (byte* srcPtr = source)
                {
                    Buffer.MemoryCopy(srcPtr, destPtr, (nuint)source.Length, (nuint)source.Length);
                }

                NotifyGuestWriteWatch(virtualAddress, source);
                return true;
            }

            if (!_hostMemory.Protect((ulong)destPtr, (ulong)source.Length, HostPageProtection.ReadWriteExecute, out var oldProtect))
            {
                return false;
            }

            try
            {
                fixed (byte* srcPtr = source)
                {
                    Buffer.MemoryCopy(srcPtr, destPtr, (nuint)source.Length, (nuint)source.Length);
                }
            }
            finally
            {
                _hostMemory.ProtectRaw((ulong)destPtr, (ulong)source.Length, oldProtect, out _);
                if (IsExecutableProtection(oldProtect))
                {
                    _hostMemory.FlushInstructionCache((ulong)destPtr, (ulong)source.Length);
                }
            }

            NotifyGuestWriteWatch(virtualAddress, source);
            return true;
        }

        return false;
    }

    private bool TryFillPatternExclusive(
        ulong virtualAddress,
        ReadOnlySpan<byte> pattern,
        ulong length)
    {
        var region = FindRegion(virtualAddress, length);
        if (region is not null &&
            TryResolveRegionOffset(virtualAddress, length, region, out var offset))
        {
            var destinationPointer = region.VirtualAddress + offset;
            if (!EnsureRangeCommitted(destinationPointer, length, region))
            {
                return false;
            }

            var destination = new Span<byte>((void*)destinationPointer, checked((int)length));
            if (CanWriteWithoutProtectionChange(destinationPointer, length, region))
            {
                FillPattern(destination, pattern);
                NotifyGuestWriteWatch(virtualAddress, destination);
                return true;
            }

            if (!_hostMemory.Protect(
                    destinationPointer,
                    length,
                    HostPageProtection.ReadWriteExecute,
                    out var oldProtect))
            {
                return false;
            }

            try
            {
                FillPattern(destination, pattern);
            }
            finally
            {
                _hostMemory.ProtectRaw(destinationPointer, length, oldProtect, out _);
                if (IsExecutableProtection(oldProtect))
                {
                    _hostMemory.FlushInstructionCache(destinationPointer, length);
                }
            }

            NotifyGuestWriteWatch(virtualAddress, destination);
            return true;
        }

        return false;
    }

    public bool TryWriteUInt64(ulong virtualAddress, ulong value)
    {
        Span<byte> buffer = stackalloc byte[sizeof(ulong)];
        BitConverter.TryWriteBytes(buffer, value);
        return TryWrite(virtualAddress, buffer);
    }

    public void* GetPointer(ulong virtualAddress)
    {
        _gate.EnterReadLock();
        try
        {
            var region = FindRegion(virtualAddress, 1);
            if (region is null)
            {
                return null;
            }

            // Raw host pointers are walked by native/JIT code without further
            // EnsureRangeCommitted calls. For reserve-only regions, commit a
            // leading working-set chunk from this address so the common case
            // does not immediately AV on the next page.
            if (region.IsReservedOnly)
            {
                var regionEnd = region.VirtualAddress + region.Size;
                var remaining = regionEnd > virtualAddress ? regionEnd - virtualAddress : 0;
                var commitBytes = Math.Min(remaining, LazyReservePrimeChunkBytes);
                if (commitBytes == 0 || !EnsureRangeCommitted(virtualAddress, commitBytes, region))
                {
                    return null;
                }
            }

            return (void*)virtualAddress;
        }
        finally
        {
            _gate.ExitReadLock();
        }
    }

    public bool IsAccessible(ulong virtualAddress, ulong size)
    {
        _gate.EnterReadLock();
        try
        {
            return FindRegion(virtualAddress, size) is not null;
        }
        finally
        {
            _gate.ExitReadLock();
        }
    }

    private bool TryResolveCopyRegionPairV1840(
        ulong sourceAddress,
        ulong destinationAddress,
        ulong length,
        out MemoryRegion sourceRegion,
        out ulong sourceOffset,
        out MemoryRegion destinationRegion,
        out ulong destinationOffset)
    {
        sourceRegion = null!;
        destinationRegion = null!;
        sourceOffset = 0;
        destinationOffset = 0;

        var generation = Volatile.Read(ref _mappingGeneration);
        var cache = _copyRegionPairCacheV1840 ??= new CopyRegionPairCacheV1840();
        if (ReferenceEquals(cache.Owner, this) &&
            cache.Generation == generation &&
            cache.SourceRegion is not null &&
            cache.DestinationRegion is not null &&
            TryResolveRegionOffset(sourceAddress, length, cache.SourceRegion, out sourceOffset) &&
            TryResolveRegionOffset(destinationAddress, length, cache.DestinationRegion, out destinationOffset))
        {
            sourceRegion = cache.SourceRegion;
            destinationRegion = cache.DestinationRegion;
            TraceCopyRegionPairCacheV1840(true, length);
            return true;
        }

        if (!TryFindRegionAndOffsetV1840(sourceAddress, length, out sourceRegion, out sourceOffset) ||
            !TryFindRegionAndOffsetV1840(destinationAddress, length, out destinationRegion, out destinationOffset))
        {
            return false;
        }

        cache.Owner = this;
        cache.Generation = generation;
        cache.SourceRegion = sourceRegion;
        cache.DestinationRegion = destinationRegion;
        TraceCopyRegionPairCacheV1840(false, length);
        return true;
    }

    private bool TryFindRegionAndOffsetV1840(
        ulong address,
        ulong size,
        out MemoryRegion region,
        out ulong offset)
    {
        var low = 0;
        var high = _regions.Count - 1;
        MemoryRegion? candidate = null;
        while (low <= high)
        {
            var middle = low + ((high - low) >> 1);
            var current = _regions[middle];
            if (current.VirtualAddress <= address)
            {
                candidate = current;
                low = middle + 1;
            }
            else
            {
                high = middle - 1;
            }
        }

        if (candidate is not null && TryResolveRegionOffset(address, size, candidate, out offset))
        {
            region = candidate;
            return true;
        }

        region = null!;
        offset = 0;
        return false;
    }

    private static void TraceCopyRegionPairCacheV1840(bool hit, ulong length)
    {
        if (!_traceCopyRegionPairCacheV1840)
        {
            return;
        }

        var count = hit
            ? ++_copyRegionPairCacheHitCountV1840
            : ++_copyRegionPairCacheMissCountV1840;
        if (count <= 16 || (count & (count - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[DBFZ-MEM-1840] vmem_copy_region_cache {(hit ? "hit" : "miss")} n={count} bytes={length}");
        }
    }
    private MemoryRegion? FindRegion(ulong address, ulong size)
    {
        var low = 0;
        var high = _regions.Count - 1;
        MemoryRegion? candidate = null;
        while (low <= high)
        {
            var middle = low + ((high - low) >> 1);
            var region = _regions[middle];
            if (region.VirtualAddress <= address)
            {
                candidate = region;
                low = middle + 1;
            }
            else
            {
                high = middle - 1;
            }
        }

        return candidate is not null &&
            TryResolveRegionOffset(address, size, candidate, out _)
                ? candidate
                : null;
    }

    private void InsertRegionSorted(MemoryRegion region)
    {
        var low = 0;
        var high = _regions.Count;
        while (low < high)
        {
            var middle = low + ((high - low) >> 1);
            if (_regions[middle].VirtualAddress < region.VirtualAddress)
            {
                low = middle + 1;
            }
            else
            {
                high = middle;
            }
        }

        if (OperatingSystem.IsWindows() && !region.IsReservedOnly)
        {
            var previous = low > 0 ? _regions[low - 1] : null;
            var next = low < _regions.Count ? _regions[low] : null;
            var mergePrevious = previous is not null &&
                !previous.IsReservedOnly &&
                previous.IsExecutable == region.IsExecutable &&
                previous.Protection == region.Protection &&
                previous.VirtualAddress + previous.Size == region.VirtualAddress;
            var mergeNext = next is not null &&
                !next.IsReservedOnly &&
                next.IsExecutable == region.IsExecutable &&
                next.Protection == region.Protection &&
                region.VirtualAddress + region.Size == next.VirtualAddress;

            if (mergePrevious && mergeNext)
            {
                previous!.Size += region.Size + next!.Size;
                _regions.RemoveAt(low);
                return;
            }

            if (mergePrevious)
            {
                previous!.Size += region.Size;
                return;
            }

            if (mergeNext)
            {
                next!.VirtualAddress = region.VirtualAddress;
                next.Size += region.Size;
                return;
            }
        }

        _regions.Insert(low, region);
    }

    private bool TryGetOverlappingRegionEnd(ulong address, ulong size, out ulong overlapEnd)
    {
        overlapEnd = 0;
        if (size == 0 || ulong.MaxValue - address < size - 1)
        {
            return false;
        }

        var end = address + size;
        _gate.EnterReadLock();
        try
        {
            foreach (var region in _regions)
            {
                var regionEnd = region.VirtualAddress + region.Size;
                if (region.VirtualAddress >= end)
                {
                    break;
                }

                if (regionEnd <= address)
                {
                    continue;
                }

                if (address < regionEnd && region.VirtualAddress < end)
                {
                    overlapEnd = Math.Max(overlapEnd, regionEnd);
                }
            }
        }
        finally
        {
            _gate.ExitReadLock();
        }

        return overlapEnd != 0;
    }

    private ulong GetAllocationSearchCursor(
        ulong desiredAddress,
        ulong requestedCursor,
        ulong alignment,
        bool executable)
    {
        lock (_allocationSearchHintGate)
        {
            var key = (desiredAddress, alignment, executable);
            if (_allocationSearchHints.TryGetValue(key, out var hintedCursor) &&
                hintedCursor > requestedCursor)
            {
                return AlignUp(hintedCursor, alignment);
            }
        }

        return requestedCursor;
    }

    private void UpdateAllocationSearchCursor(
        ulong desiredAddress,
        ulong alignment,
        bool executable,
        ulong nextCursor)
    {
        lock (_allocationSearchHintGate)
        {
            _allocationSearchHints[(desiredAddress, alignment, executable)] = AlignUp(nextCursor, alignment);
        }
    }

    private static bool TryResolveRegionOffset(ulong address, ulong size, MemoryRegion region, out ulong offset)
    {
        offset = 0;
        if (address < region.VirtualAddress)
        {
            return false;
        }

        offset = address - region.VirtualAddress;
        if (offset > region.Size)
        {
            return false;
        }

        if (size > region.Size - offset)
        {
            return false;
        }

        return true;
    }

    private static bool IsExecutableProtection(uint protection)
    {
        return protection is PAGE_EXECUTE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY;
    }

    private bool CanReadWithoutProtectionChange(ulong address, ulong size, MemoryRegion region) =>
        CanAccessWithoutProtectionChange(address, size, region, write: false);

    private bool CanWriteWithoutProtectionChange(ulong address, ulong size, MemoryRegion region) =>
        CanAccessWithoutProtectionChange(address, size, region, write: true);

    private bool CanAccessWithoutProtectionChange(ulong address, ulong size, MemoryRegion region, bool write)
    {
        var startPage = AlignDown(address, PageSize);
        var endPage = AlignUp(address + size, PageSize);
        for (var pageAddress = startPage; pageAddress < endPage; pageAddress += PageSize)
        {
            if (_pageProtections.TryGetValue(pageAddress, out var flags))
            {
                if (write ? (flags & ProgramHeaderFlags.Write) == 0 : (flags & ProgramHeaderFlags.Read) == 0)
                {
                    return false;
                }
            }
            else if (write ? !IsWritableProtection(region.Protection) : !IsReadableProtection(region.Protection))
            {
                return false;
            }
        }

        return true;
    }

    private static bool IsReadableProtection(uint protection)
    {
        return protection is PAGE_READONLY or PAGE_READWRITE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE;
    }

    private static bool IsWritableProtection(uint protection)
    {
        return protection is PAGE_READWRITE or PAGE_EXECUTE_READWRITE;
    }

    private static HostPageProtection GetCommitProtection(MemoryRegion region)
    {
        return region.IsExecutable ? HostPageProtection.ReadWriteExecute : HostPageProtection.ReadWrite;
    }

    private bool EnsureRangeCommitted(ulong address, ulong size, MemoryRegion region)
    {
        if (size == 0 || !region.IsReservedOnly)
        {
            return true;
        }

        var startPage = AlignDown(address, PageSize);
        var endPage = AlignUp(address + size, PageSize);
        var mappingGeneration = Volatile.Read(ref _mappingGeneration);
        var committedRangeCache = _committedRangeCache ??= new CommittedRangeCache();
        if (committedRangeCache.Contains(this, mappingGeneration, startPage, endPage))
        {
            return true;
        }
        var commitProtection = GetCommitProtection(region);

        var pageAddress = startPage;
        while (pageAddress < endPage)
        {
            if (!_hostMemory.Query(pageAddress, out var info))
            {
                return false;
            }

            var queriedEnd = info.RegionSize > ulong.MaxValue - info.BaseAddress
                ? ulong.MaxValue
                : info.BaseAddress + info.RegionSize;
            var rangeEnd = Math.Min(endPage, queriedEnd);
            if (rangeEnd <= pageAddress)
            {
                return false;
            }

            if (info.State == HostRegionState.Committed)
            {
                // The host query proved this whole range is committed. Retain
                // that result instead of caching only the caller's small span.
                CacheCommittedRange(info.BaseAddress, queriedEnd, mappingGeneration);
                pageAddress = rangeEnd;
                continue;
            }

            if (info.State != HostRegionState.Reserved)
            {
                return false;
            }

            var commitSize = rangeEnd - pageAddress;
            if (!_hostMemory.Commit(pageAddress, commitSize, commitProtection))
            {
                return false;
            }

            CacheCommittedRange(pageAddress, rangeEnd, mappingGeneration);
            pageAddress = rangeEnd;
        }

        CacheCommittedRange(startPage, endPage, mappingGeneration);
        return true;
    }

    private void CacheCommittedRange(ulong startPage, ulong endPage, long mappingGeneration)
    {
        (_committedRangeCache ??= new CommittedRangeCache()).Add(
            this,
            mappingGeneration,
            startPage,
            endPage);
    }

    private bool TryTemporarilyProtectForRead(
        ulong address,
        ulong size,
        MemoryRegion region,
        out List<(ulong Address, uint Protection)> touchedPages)
    {
        touchedPages = new List<(ulong Address, uint Protection)>();

        var startPage = AlignDown(address, PageSize);
        var endPage = AlignUp(address + size, PageSize);
        var temporaryProtection = region.IsExecutable ? HostPageProtection.ReadWriteExecute : HostPageProtection.ReadWrite;

        for (var pageAddress = startPage; pageAddress < endPage; pageAddress += PageSize)
        {
            if (!_hostMemory.Protect(pageAddress, PageSize, temporaryProtection, out var oldProtection))
            {
                RestorePageProtections(touchedPages);
                touchedPages.Clear();
                return false;
            }

            touchedPages.Add((pageAddress, oldProtection));
        }

        return true;
    }

    private void RestorePageProtections(List<(ulong Address, uint Protection)> touchedPages)
    {
        foreach (var (pageAddress, protection) in touchedPages)
        {
            _hostMemory.ProtectRaw(pageAddress, PageSize, protection, out _);
        }
    }

    private static ulong AlignDown(ulong value, ulong alignment)
    {
        var mask = alignment - 1;
        return value & ~mask;
    }

    private static ulong AlignUp(ulong value, ulong alignment)
    {
        var mask = alignment - 1;
        return checked((value + mask) & ~mask);
    }

    private static ulong ResolveLazyReservePrimeBytes()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_LAZY_RESERVE_PRIME_MB");
        if (ulong.TryParse(configured, out var megabytes))
        {
            return megabytes == 0
                ? 0
                : checked(Math.Min(megabytes, 4096UL) * 1024UL * 1024UL);
        }

        return DefaultLazyReservePrimeBytes;
    }

    private static void TraceVmem(string message)
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_LOG_VMEM"), "1", StringComparison.Ordinal))
        {
            return;
        }

        Log.Debug(message);
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            Clear();
            _disposed = true;
        }
    }

    private class MemoryRegion
    {
        public ulong VirtualAddress { get; set; }
        public ulong Size { get; set; }
        public bool IsExecutable { get; set; }
        public bool IsReservedOnly { get; set; }
        public uint Protection { get; set; }
    }

}
