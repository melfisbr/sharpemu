// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;

namespace SharpEmu.Libs.Gpu;

// SHARPEMU_V74_0_117_7_GUEST_RESOURCE_PROVENANCE
// A bounded, best-effort bridge between AMPR file streaming and later GPU
// consumers. The guest remains authoritative: the emulator never chooses a
// shader/asset based on the extension/path. Provenance is diagnostic metadata
// only and is never used to authorize synchronization or batching.
internal readonly record struct GuestResourceOrigin(
    long Sequence,
    uint FileId,
    string HostPath,
    string Category,
    ulong FileOffset,
    ulong Destination,
    ulong Length)
{
    public ulong EndExclusive =>
        Destination > ulong.MaxValue - Length
            ? ulong.MaxValue
            : Destination + Length;
}

internal static class GuestResourceProvenance
{
    private const int PageShift = 16; // 64 KiB lookup buckets.
    private const ulong PageSize = 1UL << PageShift;
    private const int MaxPagesPerRead = 64;
    private const int MaxTrackedPagesBeforeTrim = 262_144;

    private static readonly ConcurrentDictionary<ulong, GuestResourceOrigin> _pageOrigins = new();
    private static readonly ConcurrentDictionary<ulong, GuestResourceOrigin> _exactOrigins = new();
    private static readonly ConcurrentDictionary<(string Kind, ulong Address), byte> _seenConsumers = new();
    private static readonly ConcurrentDictionary<string, long> _registeredByCategory =
        new(StringComparer.OrdinalIgnoreCase);

    private static long _sequence;
    private static long _registrations;
    private static long _registeredBytes;
    private static long _queries;
    private static long _hits;
    private static long _misses;
    private static long _consumerTraces;
    private static long _trims;

    internal static bool Enabled =>
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_GUEST_RESOURCE_PROVENANCE"),
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

        var sequence = Interlocked.Increment(ref _sequence);
        if (_pageOrigins.Count > MaxTrackedPagesBeforeTrim &&
            (sequence & 0x3FF) == 0)
        {
            _pageOrigins.Clear();
            _exactOrigins.Clear();
            _seenConsumers.Clear();
            Interlocked.Increment(ref _trims);
        }

        var origin = new GuestResourceOrigin(
            sequence,
            fileId,
            hostPath,
            GetCategory(hostPath),
            fileOffset,
            destination,
            bytesRead);

        _exactOrigins[destination] = origin;

        var endInclusive = destination > ulong.MaxValue - (bytesRead - 1)
            ? ulong.MaxValue
            : destination + bytesRead - 1;
        var firstPage = destination >> PageShift;
        var lastPage = endInclusive >> PageShift;
        var pageCount = lastPage >= firstPage
            ? lastPage - firstPage + 1
            : 1;

        if (pageCount <= MaxPagesPerRead)
        {
            for (var page = firstPage; page <= lastPage; page++)
            {
                _pageOrigins[page] = origin;
                if (page == ulong.MaxValue)
                {
                    break;
                }
            }
        }
        else
        {
            // Large assets are uncommon; sample both ends without allowing a
            // single read to flood the lookup map.
            const ulong half = MaxPagesPerRead / 2;
            for (ulong index = 0; index < half; index++)
            {
                _pageOrigins[firstPage + index] = origin;
                _pageOrigins[lastPage - index] = origin;
            }
        }

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
                $"[V74.0.117.7][APR_RESOURCE_ORIGIN] " +
                $"seq={sequence} id=0x{fileId:X8} category={origin.Category} " +
                $"dst=0x{destination:X16} bytes=0x{bytesRead:X} " +
                $"file_off=0x{fileOffset:X} path='{hostPath}'");
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
        if (length == 0)
        {
            length = 1;
        }

        if (_exactOrigins.TryGetValue(address, out var exact) &&
            Contains(exact, address, length))
        {
            origin = exact;
            Interlocked.Increment(ref _hits);
            return true;
        }

        if (_pageOrigins.TryGetValue(address >> PageShift, out var candidate) &&
            Contains(candidate, address, length))
        {
            origin = candidate;
            Interlocked.Increment(ref _hits);
            return true;
        }

        Interlocked.Increment(ref _misses);
        return false;
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
        if (trace > 256 && (trace & (trace - 1)) != 0)
        {
            return;
        }

        if (hit)
        {
            Console.Error.WriteLine(
                $"[V74.0.117.7][GPU_RESOURCE_ORIGIN] " +
                $"count={trace} kind={kind} addr=0x{address:X16} " +
                $"bytes=0x{length:X} shader=0x{shaderAddress:X16} " +
                $"source_seq={origin.Sequence} id=0x{origin.FileId:X8} " +
                $"category={origin.Category} source_dst=0x{origin.Destination:X16} " +
                $"source_bytes=0x{origin.Length:X} file_off=0x{origin.FileOffset:X} " +
                $"path='{origin.HostPath}' confidence=direct-apr-range");
        }
        else
        {
            Console.Error.WriteLine(
                $"[V74.0.117.7][GPU_RESOURCE_ORIGIN] " +
                $"count={trace} kind={kind} addr=0x{address:X16} " +
                $"bytes=0x{length:X} shader=0x{shaderAddress:X16} " +
                "source=unknown reason=no-direct-apr-range");
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
            $"[V74.0.117.7][GUEST_RESOURCE_PROVENANCE_SUMMARY] " +
            $"registrations={Volatile.Read(ref _registrations)} " +
            $"registered_mb={Volatile.Read(ref _registeredBytes) / (1024.0 * 1024.0):F2} " +
            $"tracked_pages={_pageOrigins.Count} exact_bases={_exactOrigins.Count} " +
            $"queries={Volatile.Read(ref _queries)} hits={Volatile.Read(ref _hits)} " +
            $"misses={Volatile.Read(ref _misses)} consumer_traces={Volatile.Read(ref _consumerTraces)} " +
            $"trims={Volatile.Read(ref _trims)} categories=[{categories}]");
    }

    private static bool Contains(
        GuestResourceOrigin origin,
        ulong address,
        ulong length)
    {
        if (address < origin.Destination)
        {
            return false;
        }

        var end = address > ulong.MaxValue - length
            ? ulong.MaxValue
            : address + length;
        return end <= origin.EndExclusive;
    }

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
