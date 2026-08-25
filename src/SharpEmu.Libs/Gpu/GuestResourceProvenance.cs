// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;

namespace SharpEmu.Libs.Gpu;

// SHARPEMU_V74_0_117_8_GUEST_MEMORY_PROVENANCE_PROPAGATION
// Structural provenance bridge v2. APR still defines the authoritative file
// origin. This layer propagates that metadata through proven guest-memory copy
// operations only. It never changes guest bytes, file ordering, shader choice,
// synchronization, batching eligibility, or Vulkan submission semantics.
internal readonly record struct GuestResourceOrigin(
    long Sequence,
    uint FileId,
    string HostPath,
    string Category,
    ulong FileOffset,
    ulong Destination,
    ulong Length,
    string Route,
    int CopyDepth)
{
    public ulong EndExclusive =>
        Destination > ulong.MaxValue - Length
            ? ulong.MaxValue
            : Destination + Length;
}

internal static class GuestResourceProvenance
{
    private const int PageShift = 16; // 64 KiB provenance buckets.
    private const ulong PageSize = 1UL << PageShift;
    private const int MaxOriginsPerPage = 6;
    private const ulong MaxPagesPerOrigin = 16_384; // 1 GiB at 64 KiB/page.
    private const int MaxTrackedPagesBeforeTrim = 524_288;
    private const int MaxCopySegmentsPerOperation = 8_192;

    private sealed class PageOriginBucket
    {
        private readonly object _gate = new();
        private readonly List<GuestResourceOrigin> _origins = new(MaxOriginsPerPage);

        internal void Add(GuestResourceOrigin origin)
        {
            lock (_gate)
            {
                for (var index = _origins.Count - 1; index >= 0; index--)
                {
                    var existing = _origins[index];
                    if (existing.Destination == origin.Destination &&
                        existing.Length == origin.Length &&
                        existing.FileId == origin.FileId &&
                        existing.FileOffset == origin.FileOffset)
                    {
                        _origins.RemoveAt(index);
                    }
                }

                _origins.Add(origin);
                while (_origins.Count > MaxOriginsPerPage)
                {
                    _origins.RemoveAt(0);
                }
            }
        }

        internal bool TryResolve(ulong address, out GuestResourceOrigin origin)
        {
            lock (_gate)
            {
                for (var index = _origins.Count - 1; index >= 0; index--)
                {
                    var candidate = _origins[index];
                    if (address >= candidate.Destination && address < candidate.EndExclusive)
                    {
                        origin = candidate;
                        return true;
                    }
                }
            }

            origin = default;
            return false;
        }

        internal void RemoveOverlapping(ulong start, ulong endExclusive)
        {
            lock (_gate)
            {
                for (var index = _origins.Count - 1; index >= 0; index--)
                {
                    var origin = _origins[index];
                    if (start < origin.EndExclusive && origin.Destination < endExclusive)
                    {
                        _origins.RemoveAt(index);
                    }
                }
            }
        }

        internal bool IsEmpty
        {
            get
            {
                lock (_gate)
                {
                    return _origins.Count == 0;
                }
            }
        }
    }

    private readonly record struct CopySegment(
        GuestResourceOrigin SourceOrigin,
        ulong SourceAddress,
        ulong DestinationAddress,
        ulong Length);

    private static readonly ConcurrentDictionary<ulong, PageOriginBucket> _pageOrigins = new();
    private static readonly ConcurrentDictionary<(string Kind, ulong Address), byte> _seenConsumers = new();
    private static readonly ConcurrentDictionary<string, long> _registeredByCategory =
        new(StringComparer.OrdinalIgnoreCase);

    private static long _sequence;
    private static long _registrations;
    private static long _registeredBytes;
    private static long _queries;
    private static long _hits;
    private static long _partialHits;
    private static long _misses;
    private static long _consumerTraces;
    private static long _trims;
    private static long _copyAttempts;
    private static long _copySourceHits;
    private static long _copySegments;
    private static long _copyBytes;
    private static long _copyUnknownBytes;
    private static long _copyTraceCount;
    private static long _invalidatedPages;
    private static int _maxCopyDepth;

    internal static bool Enabled =>
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_GUEST_RESOURCE_PROVENANCE"),
            "1",
            StringComparison.Ordinal);

    internal static bool CopyPropagationEnabled =>
        Enabled &&
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_GUEST_RESOURCE_PROVENANCE_PROPAGATE_COPY"),
            "1",
            StringComparison.Ordinal);

    internal static void RegisterAprRead(
        uint fileId,
        string hostPath,
        ulong fileOffset,
        ulong destination,
        ulong bytesRead)
    {
        if (!Enabled ||
            string.IsNullOrWhiteSpace(hostPath) ||
            destination == 0 ||
            bytesRead == 0)
        {
            return;
        }

        var sequence = NextSequenceAndMaybeTrim();
        var origin = new GuestResourceOrigin(
            sequence,
            fileId,
            hostPath,
            GetCategory(hostPath),
            fileOffset,
            destination,
            bytesRead,
            "apr-direct",
            0);

        IndexOrigin(origin);

        Interlocked.Increment(ref _registrations);
        Interlocked.Add(
            ref _registeredBytes,
            bytesRead > long.MaxValue ? long.MaxValue : (long)bytesRead);
        _registeredByCategory.AddOrUpdate(
            origin.Category,
            1,
            static (_, current) => current + 1);

        if (sequence <= 64 || (sequence & (sequence - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.117.8][APR_RESOURCE_ORIGIN] " +
                $"seq={sequence} id=0x{fileId:X8} category={origin.Category} " +
                $"dst=0x{destination:X16} bytes=0x{bytesRead:X} " +
                $"file_off=0x{fileOffset:X} path='{hostPath}'");
        }
    }

    internal static void PropagateCopy(
        ulong sourceAddress,
        ulong destinationAddress,
        ulong length,
        string route)
    {
        if (!CopyPropagationEnabled ||
            sourceAddress == 0 ||
            destinationAddress == 0 ||
            length == 0 ||
            sourceAddress == destinationAddress)
        {
            return;
        }

        Interlocked.Increment(ref _copyAttempts);

        // Resolve every known source segment before invalidating destination
        // metadata so overlapping memmove semantics cannot destroy their own
        // provenance while the operation is being classified.
        var segments = new List<CopySegment>(4);
        ulong resolvedBytes = 0;
        ulong offset = 0;
        while (offset < length && segments.Count < MaxCopySegmentsPerOperation)
        {
            var source = SaturatingAdd(sourceAddress, offset);
            var destination = SaturatingAdd(destinationAddress, offset);
            if (source == ulong.MaxValue || destination == ulong.MaxValue)
            {
                break;
            }

            if (TryResolvePoint(source, out var origin))
            {
                var available = origin.EndExclusive > source
                    ? origin.EndExclusive - source
                    : 0;
                var segmentLength = Math.Min(length - offset, available);
                if (segmentLength != 0)
                {
                    segments.Add(new CopySegment(origin, source, destination, segmentLength));
                    resolvedBytes = SaturatingAdd(resolvedBytes, segmentLength);
                    offset += segmentLength;
                    continue;
                }
            }

            // Unknown range: advance to the next provenance bucket rather than
            // walking byte-by-byte through a large transformed allocation.
            var withinPage = source & (PageSize - 1);
            var skip = Math.Min(length - offset, PageSize - withinPage);
            if (skip == 0)
            {
                break;
            }

            offset += skip;
        }

        InvalidateDestinationRange(destinationAddress, length);

        var maxDepthThisCopy = 0;
        foreach (var segment in segments)
        {
            var sourceDelta = segment.SourceAddress - segment.SourceOrigin.Destination;
            var fileOffset = SaturatingAdd(segment.SourceOrigin.FileOffset, sourceDelta);
            var depth = segment.SourceOrigin.CopyDepth + 1;
            maxDepthThisCopy = Math.Max(maxDepthThisCopy, depth);
            var derived = new GuestResourceOrigin(
                NextSequenceAndMaybeTrim(),
                segment.SourceOrigin.FileId,
                segment.SourceOrigin.HostPath,
                segment.SourceOrigin.Category,
                fileOffset,
                segment.DestinationAddress,
                segment.Length,
                string.IsNullOrWhiteSpace(route) ? "guest-copy" : route,
                depth);
            IndexOrigin(derived);
        }

        if (resolvedBytes != 0)
        {
            Interlocked.Increment(ref _copySourceHits);
            Interlocked.Add(ref _copySegments, segments.Count);
            Interlocked.Add(
                ref _copyBytes,
                resolvedBytes > long.MaxValue ? long.MaxValue : (long)resolvedBytes);
            UpdateMaxCopyDepth(maxDepthThisCopy);
        }

        var unknownBytes = length > resolvedBytes ? length - resolvedBytes : 0;
        if (unknownBytes != 0)
        {
            Interlocked.Add(
                ref _copyUnknownBytes,
                unknownBytes > long.MaxValue ? long.MaxValue : (long)unknownBytes);
        }

        var trace = Interlocked.Increment(ref _copyTraceCount);
        if (trace <= 64 || (trace & (trace - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.117.8][PROVENANCE_COPY] count={trace} route={route} " +
                $"src=0x{sourceAddress:X16} dst=0x{destinationAddress:X16} " +
                $"bytes=0x{length:X} resolved=0x{resolvedBytes:X} " +
                $"segments={segments.Count} max_depth={maxDepthThisCopy}");
        }
    }

    internal static void InvalidateRange(
        ulong destinationAddress,
        ulong length,
        string reason)
    {
        if (!CopyPropagationEnabled || destinationAddress == 0 || length == 0)
        {
            return;
        }

        InvalidateDestinationRange(destinationAddress, length);
        if (ShouldTraceSparse(Interlocked.Read(ref _invalidatedPages)))
        {
            Console.Error.WriteLine(
                $"[V74.0.117.8][PROVENANCE_INVALIDATE] reason={reason} " +
                $"dst=0x{destinationAddress:X16} bytes=0x{length:X}");
        }
    }

    internal static bool TryResolve(
        ulong address,
        ulong length,
        out GuestResourceOrigin origin)
    {
        origin = default;
        if (!Enabled || address == 0)
        {
            return false;
        }

        Interlocked.Increment(ref _queries);
        if (!TryResolvePoint(address, out origin))
        {
            Interlocked.Increment(ref _misses);
            return false;
        }

        if (length == 0)
        {
            length = 1;
        }

        var end = SaturatingAdd(address, length);
        if (end <= origin.EndExclusive)
        {
            Interlocked.Increment(ref _hits);
        }
        else
        {
            // The resource begins in a proven origin but spans farther than the
            // currently tracked segment. This remains useful diagnostic provenance
            // but is explicitly counted as partial coverage.
            Interlocked.Increment(ref _partialHits);
            Interlocked.Increment(ref _hits);
        }

        return true;
    }

    internal static void TraceConsumer(
        string kind,
        ulong address,
        ulong length,
        ulong shaderAddress)
    {
        if (!Enabled || address == 0 || !_seenConsumers.TryAdd((kind, address), 0))
        {
            return;
        }

        var hit = TryResolve(address, length, out var origin);
        var trace = Interlocked.Increment(ref _consumerTraces);
        if (trace > 512 && (trace & (trace - 1)) != 0)
        {
            return;
        }

        if (hit)
        {
            var coverage = origin.EndExclusive > address
                ? Math.Min(length == 0 ? 1UL : length, origin.EndExclusive - address)
                : 0;
            var confidence = origin.CopyDepth == 0
                ? "direct-apr-range"
                : "propagated-copy-range";
            Console.Error.WriteLine(
                $"[V74.0.117.8][GPU_RESOURCE_ORIGIN] " +
                $"count={trace} kind={kind} addr=0x{address:X16} " +
                $"bytes=0x{length:X} covered=0x{coverage:X} shader=0x{shaderAddress:X16} " +
                $"source_seq={origin.Sequence} id=0x{origin.FileId:X8} " +
                $"category={origin.Category} source_dst=0x{origin.Destination:X16} " +
                $"source_bytes=0x{origin.Length:X} file_off=0x{origin.FileOffset:X} " +
                $"copy_depth={origin.CopyDepth} route={origin.Route} " +
                $"path='{origin.HostPath}' confidence={confidence}");
        }
        else
        {
            Console.Error.WriteLine(
                $"[V74.0.117.8][GPU_RESOURCE_ORIGIN] " +
                $"count={trace} kind={kind} addr=0x{address:X16} " +
                $"bytes=0x{length:X} shader=0x{shaderAddress:X16} " +
                "source=unknown reason=no-known-apr-or-copy-range");
        }
    }

    internal static void TraceSummary()
    {
        if (!Enabled)
        {
            return;
        }

        var categories = string.Join(
            ',',
            _registeredByCategory
                .OrderBy(static pair => pair.Key, StringComparer.OrdinalIgnoreCase)
                .Select(static pair => $"{pair.Key}:{pair.Value}"));

        Console.Error.WriteLine(
            $"[V74.0.117.8][GUEST_RESOURCE_PROVENANCE_SUMMARY] " +
            $"registrations={Volatile.Read(ref _registrations)} " +
            $"registered_mb={Volatile.Read(ref _registeredBytes) / (1024.0 * 1024.0):F2} " +
            $"tracked_pages={_pageOrigins.Count} " +
            $"queries={Volatile.Read(ref _queries)} hits={Volatile.Read(ref _hits)} " +
            $"partial_hits={Volatile.Read(ref _partialHits)} " +
            $"misses={Volatile.Read(ref _misses)} consumer_traces={Volatile.Read(ref _consumerTraces)} " +
            $"copy_attempts={Volatile.Read(ref _copyAttempts)} " +
            $"copy_source_hits={Volatile.Read(ref _copySourceHits)} " +
            $"copy_segments={Volatile.Read(ref _copySegments)} " +
            $"copy_mb={Volatile.Read(ref _copyBytes) / (1024.0 * 1024.0):F2} " +
            $"copy_unknown_mb={Volatile.Read(ref _copyUnknownBytes) / (1024.0 * 1024.0):F2} " +
            $"max_copy_depth={Volatile.Read(ref _maxCopyDepth)} " +
            $"invalidated_pages={Volatile.Read(ref _invalidatedPages)} " +
            $"trims={Volatile.Read(ref _trims)} categories=[{categories}]");
    }

    private static long NextSequenceAndMaybeTrim()
    {
        var sequence = Interlocked.Increment(ref _sequence);
        if (_pageOrigins.Count > MaxTrackedPagesBeforeTrim &&
            (sequence & 0x3FF) == 0)
        {
            _pageOrigins.Clear();
            _seenConsumers.Clear();
            Interlocked.Increment(ref _trims);
        }

        return sequence;
    }

    private static void IndexOrigin(GuestResourceOrigin origin)
    {
        if (origin.Length == 0)
        {
            return;
        }

        var endInclusive = origin.Destination > ulong.MaxValue - (origin.Length - 1)
            ? ulong.MaxValue
            : origin.Destination + origin.Length - 1;
        var firstPage = origin.Destination >> PageShift;
        var lastPage = endInclusive >> PageShift;
        var pageCount = lastPage >= firstPage
            ? lastPage - firstPage + 1
            : 1;

        if (pageCount <= MaxPagesPerOrigin)
        {
            for (var page = firstPage; page <= lastPage; page++)
            {
                _pageOrigins.GetOrAdd(page, static _ => new PageOriginBucket()).Add(origin);
                if (page == ulong.MaxValue)
                {
                    break;
                }
            }

            return;
        }

        // Extremely large regions are sparsely indexed rather than flooding
        // the map. Ordinary Demon's Souls APR reads are far below this bound.
        var stride = Math.Max(1UL, pageCount / MaxPagesPerOrigin);
        ulong indexed = 0;
        for (var page = firstPage; page <= lastPage && indexed < MaxPagesPerOrigin; page += stride)
        {
            _pageOrigins.GetOrAdd(page, static _ => new PageOriginBucket()).Add(origin);
            indexed++;
            if (page > ulong.MaxValue - stride)
            {
                break;
            }
        }
        _pageOrigins.GetOrAdd(lastPage, static _ => new PageOriginBucket()).Add(origin);
    }

    private static bool TryResolvePoint(ulong address, out GuestResourceOrigin origin)
    {
        if (_pageOrigins.TryGetValue(address >> PageShift, out var bucket) &&
            bucket.TryResolve(address, out origin))
        {
            return true;
        }

        origin = default;
        return false;
    }

    private static void InvalidateDestinationRange(ulong destinationAddress, ulong length)
    {
        if (length == 0)
        {
            return;
        }

        var endExclusive = SaturatingAdd(destinationAddress, length);
        var endInclusive = endExclusive == ulong.MaxValue
            ? ulong.MaxValue
            : endExclusive - 1;
        var firstPage = destinationAddress >> PageShift;
        var lastPage = endInclusive >> PageShift;
        for (var page = firstPage; page <= lastPage; page++)
        {
            if (_pageOrigins.TryGetValue(page, out var bucket))
            {
                bucket.RemoveOverlapping(destinationAddress, endExclusive);
                if (bucket.IsEmpty)
                {
                    _pageOrigins.TryRemove(page, out _);
                }
                Interlocked.Increment(ref _invalidatedPages);
            }

            if (page == ulong.MaxValue)
            {
                break;
            }
        }
    }

    private static ulong SaturatingAdd(ulong left, ulong right) =>
        left > ulong.MaxValue - right ? ulong.MaxValue : left + right;

    private static void UpdateMaxCopyDepth(int depth)
    {
        while (true)
        {
            var current = Volatile.Read(ref _maxCopyDepth);
            if (depth <= current)
            {
                return;
            }

            if (Interlocked.CompareExchange(ref _maxCopyDepth, depth, current) == current)
            {
                return;
            }
        }
    }

    private static bool ShouldTraceSparse(long value) =>
        value <= 64 || (value > 0 && (value & (value - 1)) == 0);

    private static string GetCategory(string hostPath)
    {
        var extension = Path.GetExtension(hostPath).ToLowerInvariant();
        return extension switch
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
    }
}
