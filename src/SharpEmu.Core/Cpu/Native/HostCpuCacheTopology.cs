// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Runtime.InteropServices;

namespace SharpEmu.Core.Cpu.Native;

/// <summary>
/// Windows-only, process-local CPU topology helper used to keep guest threads
/// on real physical cores before SMT siblings while respecting shared L3
/// domains. It never changes process affinity, system cache policy, MTRRs, PAT,
/// power plans or thread priority. If discovery fails, callers fall back to the
/// legacy SharpEmu mapper.
/// </summary>
internal static class HostCpuCacheTopology
{
    private const int RelationProcessorCore = 0;
    private const int RelationCache = 2;
    private const int ErrorInsufficientBuffer = 122;
    private const int CacheUnified = 0;
    private const int CacheData = 2;

    private static readonly string CachePolicy = NormalizePolicy(
        Environment.GetEnvironmentVariable("SHARPEMU_CPU_CACHE_POLICY"));

    private static readonly bool CacheAwareEnabled =
        !string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_CPU_CACHE_AWARE"), "0", StringComparison.Ordinal) &&
        !string.Equals(CachePolicy, "legacy", StringComparison.Ordinal);

    private static readonly bool CacheLogEnabled =
        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_CPU_CACHE_LOG"), "1", StringComparison.Ordinal);

    private static readonly bool AffinityVerifyEnabled =
        string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_CPU_CACHE_VERIFY"), "1", StringComparison.Ordinal);

    internal static bool LoggingEnabled => CacheLogEnabled;
    internal static bool VerificationEnabled => CacheAwareEnabled && AffinityVerifyEnabled;

    private static readonly Lazy<Topology?> DetectedTopology = new(DetectTopology, isThreadSafe: true);
    private static readonly object LaneOrderGate = new();
    private static readonly Dictionary<(int Reserved, string Policy), int[]> LaneOrderCache = new();
    private static int _topologyLogged;

    internal static bool TryMapGuestAffinity(
        ulong guestAffinityMask,
        int reservedHostLanes,
        out ulong hostAffinityMask)
    {
        hostAffinityMask = 0;
        if (!CacheAwareEnabled || !OperatingSystem.IsWindows() ||
            guestAffinityMask == 0 || guestAffinityMask == ulong.MaxValue ||
            Environment.ProcessorCount <= 1 || Environment.ProcessorCount > 64)
        {
            return false;
        }

        var topology = DetectedTopology.Value;
        if (topology is null || topology.Cores.Length == 0)
        {
            return false;
        }

        var lanes = GetLaneOrder(topology, reservedHostLanes, CachePolicy);
        if (lanes.Length == 0)
        {
            return false;
        }

        for (var guestCpu = 0; guestCpu < 64; guestCpu++)
        {
            if ((guestAffinityMask & (1UL << guestCpu)) == 0)
            {
                continue;
            }

            var hostCpu = lanes[guestCpu % lanes.Length];
            if ((uint)hostCpu < 64u)
            {
                hostAffinityMask |= 1UL << hostCpu;
            }
        }

        if (hostAffinityMask == 0)
        {
            return false;
        }

        TraceTopologyOnce(topology, lanes, reservedHostLanes, CachePolicy);
        return true;
    }

    internal static string DescribeHostAffinity(ulong hostAffinityMask)
    {
        var topology = DetectedTopology.Value;
        if (topology is null || hostAffinityMask == 0)
        {
            return "unknown";
        }

        var placements = new List<string>();
        foreach (var logicalProcessor in EnumerateBits(hostAffinityMask))
        {
            var coreIndex = Array.FindIndex(
                topology.Cores,
                core => (core.Mask & (1UL << logicalProcessor)) != 0);
            if (coreIndex < 0)
            {
                placements.Add($"cpu{logicalProcessor}/core?/l3?");
                continue;
            }

            var core = topology.Cores[coreIndex];
            var smtRole = logicalProcessor == core.PrimaryLogicalProcessor ? "primary" : "smt";
            var l3 = core.L3Index >= 0 ? $"l3#{core.L3Index}" : "l3?";
            placements.Add($"cpu{logicalProcessor}/core{coreIndex}/{l3}/{smtRole}");
        }

        return string.Join(",", placements);
    }

    internal static bool TryDescribeLogicalProcessor(
        int logicalProcessor,
        out int physicalCoreIndex,
        out int l3Index)
    {
        physicalCoreIndex = -1;
        l3Index = -1;
        if ((uint)logicalProcessor >= 64u)
        {
            return false;
        }

        var topology = DetectedTopology.Value;
        if (topology is null)
        {
            return false;
        }

        var bit = 1UL << logicalProcessor;
        for (var index = 0; index < topology.Cores.Length; index++)
        {
            if ((topology.Cores[index].Mask & bit) == 0)
            {
                continue;
            }

            physicalCoreIndex = index;
            l3Index = topology.Cores[index].L3Index;
            return true;
        }

        return false;
    }

    internal static int CountL3Domains(ulong hostAffinityMask)
    {
        var topology = DetectedTopology.Value;
        if (topology is null || hostAffinityMask == 0)
        {
            return 0;
        }

        return topology.Cores
            .Where(core => core.L3Index >= 0 && (core.Mask & hostAffinityMask) != 0)
            .Select(core => core.L3Index)
            .Distinct()
            .Count();
    }

    private static int[] GetLaneOrder(Topology topology, int reservedHostLanes, string policy)
    {
        reservedHostLanes = Math.Max(0, reservedHostLanes);
        lock (LaneOrderGate)
        {
            var key = (reservedHostLanes, policy);
            if (LaneOrderCache.TryGetValue(key, out var cached))
            {
                return cached;
            }

            var orderedCores = OrderCores(topology.Cores, policy);
            var typicalThreadsPerCore = Math.Max(
                1,
                (int)Math.Round(orderedCores.Average(core => BitOperations.PopCount(core.Mask))));
            var reserveCoreCount = (reservedHostLanes + typicalThreadsPerCore - 1) / typicalThreadsPerCore;

            // Never let cache tuning starve the guest. On machines with at least
            // two physical cores, keep two available even when an aggressive
            // SHARPEMU_RESERVED_HOST_LANES value is supplied.
            var minimumGuestCores = orderedCores.Length >= 2 ? 2 : 1;
            reserveCoreCount = Math.Min(
                reserveCoreCount,
                Math.Max(0, orderedCores.Length - minimumGuestCores));

            var eligible = orderedCores
                .Take(orderedCores.Length - reserveCoreCount)
                .ToArray();

            var lanes = new List<int>(eligible.Sum(core => BitOperations.PopCount(core.Mask)));

            // First pass: one logical processor per physical core.
            foreach (var core in eligible)
            {
                lanes.Add(core.PrimaryLogicalProcessor);
            }

            // Second pass: SMT siblings. This guarantees that a second hardware
            // thread is not used while an unused physical core is still free.
            foreach (var core in eligible)
            {
                foreach (var sibling in EnumerateBits(core.Mask))
                {
                    if (sibling != core.PrimaryLogicalProcessor)
                    {
                        lanes.Add(sibling);
                    }
                }
            }

            var result = lanes.Distinct().ToArray();
            LaneOrderCache[key] = result;
            return result;
        }
    }

    private static CoreInfo[] OrderCores(CoreInfo[] cores, string policy)
    {
        var baseOrder = cores.OrderBy(core => core.PrimaryLogicalProcessor).ToArray();
        if (policy != "spread")
        {
            // auto/compact preserve L3 locality: fill physical cores from the
            // same shared L3 domain before moving to the next domain.
            return baseOrder
                .OrderBy(core => core.L3Index < 0 ? int.MaxValue : core.L3Index)
                .ThenBy(core => core.PrimaryLogicalProcessor)
                .ToArray();
        }

        // spread is an explicit throughput experiment: round-robin physical
        // cores across L3 domains to expose more aggregate cache bandwidth.
        var groups = baseOrder
            .GroupBy(core => core.L3Index)
            .OrderBy(group => group.Key < 0 ? int.MaxValue : group.Key)
            .Select(group => new Queue<CoreInfo>(group.OrderBy(core => core.PrimaryLogicalProcessor)))
            .ToArray();
        var result = new List<CoreInfo>(baseOrder.Length);
        var progress = true;
        while (progress)
        {
            progress = false;
            foreach (var group in groups)
            {
                if (group.Count == 0)
                {
                    continue;
                }

                result.Add(group.Dequeue());
                progress = true;
            }
        }

        return result.ToArray();
    }

    private static Topology? DetectTopology()
    {
        if (!OperatingSystem.IsWindows() || !Environment.Is64BitProcess || Environment.ProcessorCount > 64)
        {
            return null;
        }

        try
        {
            var processMask = ReadCurrentProcessAffinityMask();
            if (processMask == 0)
            {
                return null;
            }

            var coreMasks = ReadProcessorCoreMasks(processMask);
            if (coreMasks.Count == 0)
            {
                return null;
            }

            var l3Caches = ReadL3Caches(processMask, out var l3DiscoveryMode, out var l3RecordsSeen);
            var cores = new CoreInfo[coreMasks.Count];
            for (var index = 0; index < coreMasks.Count; index++)
            {
                var coreMask = coreMasks[index];
                var l3Index = -1;
                for (var cacheIndex = 0; cacheIndex < l3Caches.Count; cacheIndex++)
                {
                    if ((l3Caches[cacheIndex].Mask & coreMask) != 0)
                    {
                        l3Index = cacheIndex;
                        break;
                    }
                }

                cores[index] = new CoreInfo(
                    coreMask,
                    BitOperations.TrailingZeroCount(coreMask),
                    l3Index);
            }

            return new Topology(
                processMask,
                cores.OrderBy(core => core.PrimaryLogicalProcessor).ToArray(),
                l3Caches.ToArray(),
                l3DiscoveryMode,
                l3RecordsSeen);
        }
        catch (Exception exception)
        {
            if (CacheLogEnabled)
            {
                Console.Error.WriteLine(
                    $"[CPU-CACHE][WARN] topology discovery failed; legacy mapping retained: {exception.GetType().Name}: {exception.Message}");
            }

            return null;
        }
    }

    private static List<ulong> ReadProcessorCoreMasks(ulong processMask)
    {
        var masks = new List<ulong>();
        WithLogicalProcessorBuffer(RelationProcessorCore, (entry, relationship, size) =>
        {
            if (relationship != RelationProcessorCore || size < 48)
            {
                return;
            }

            var groupCount = unchecked((ushort)Marshal.ReadInt16(entry, 30));
            var mask = ReadGroupZeroMask(entry, groupCount, firstGroupAffinityOffset: 32) & processMask;
            if (mask != 0 && !masks.Contains(mask))
            {
                masks.Add(mask);
            }
        });
        masks.Sort((left, right) => BitOperations.TrailingZeroCount(left).CompareTo(BitOperations.TrailingZeroCount(right)));
        return masks;
    }

    private static List<L3Info> ReadL3Caches(
        ulong processMask,
        out string discoveryMode,
        out int recordsSeen)
    {
        var caches = new List<L3Info>();
        var legacySingleMaskRecords = 0;
        var groupCountRecords = 0;
        var localRecordsSeen = 0;

        WithLogicalProcessorBuffer(RelationCache, (entry, relationship, size) =>
        {
            if (relationship != RelationCache || size < 56)
            {
                return;
            }

            var level = Marshal.ReadByte(entry, 8);
            var cacheType = Marshal.ReadInt32(entry, 16);
            if (level != 3 || (cacheType != CacheUnified && cacheType != CacheData))
            {
                return;
            }

            localRecordsSeen++;
            var cacheSize = unchecked((uint)Marshal.ReadInt32(entry, 12));
            var lineSize = unchecked((ushort)Marshal.ReadInt16(entry, 10));

            // CACHE_RELATIONSHIP has two ABI shapes in the Windows 10/11
            // ecosystem. Newer headers expose Reserved[18] + GroupCount +
            // GroupMasks[]. Older Windows implementations expose Reserved[20]
            // + one GroupMask. Both place the first GROUP_AFFINITY at byte 40
            // of SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, but on the older ABI
            // bytes 38..39 are reserved and therefore normally zero.
            //
            // Treat GroupCount==0 as the documented legacy single-mask layout
            // instead of rejecting the cache. This is critical on Windows 10
            // hosts where the processor/core records are valid but L3 would
            // otherwise be reported as l3_domains=0.
            var groupCount = unchecked((ushort)Marshal.ReadInt16(entry, 38));
            ulong mask;
            if (groupCount == 0)
            {
                mask = ReadSingleGroupMask(entry, firstGroupAffinityOffset: 40) & processMask;
                legacySingleMaskRecords++;
            }
            else
            {
                var maximumReadableGroups = Math.Max(0, (size - 40) / 16);
                var readableGroupCount = Math.Min((int)groupCount, maximumReadableGroups);
                mask = readableGroupCount > 0
                    ? ReadGroupZeroMask(entry, unchecked((ushort)readableGroupCount), firstGroupAffinityOffset: 40) & processMask
                    : 0;
                groupCountRecords++;
            }

            if (mask == 0 || caches.Any(cache => cache.Mask == mask))
            {
                return;
            }

            caches.Add(new L3Info(mask, cacheSize, lineSize));
        });

        // A second, independent Windows API fallback is intentionally kept for
        // <=64 logical-processor hosts. It uses the fixed-size legacy topology
        // record and is safe here because DetectTopology already rejects >64.
        // This makes cache discovery resilient if a vendor/OS combination
        // returns RelationCache records that cannot be decoded by either EX ABI.
        if (caches.Count == 0)
        {
            var legacyApiCaches = ReadL3CachesLegacyApi(processMask);
            if (legacyApiCaches.Count != 0)
            {
                caches.AddRange(legacyApiCaches);
                discoveryMode = "legacy-api";
                recordsSeen = localRecordsSeen;
                caches.Sort((left, right) => BitOperations.TrailingZeroCount(left.Mask).CompareTo(BitOperations.TrailingZeroCount(right.Mask)));
                return caches;
            }
        }

        recordsSeen = localRecordsSeen;
        discoveryMode = legacySingleMaskRecords != 0 && groupCountRecords != 0
            ? "ex-mixed"
            : legacySingleMaskRecords != 0
                ? "ex-legacy-single-mask"
                : groupCountRecords != 0
                    ? "ex-groupcount"
                    : "none";

        caches.Sort((left, right) => BitOperations.TrailingZeroCount(left.Mask).CompareTo(BitOperations.TrailingZeroCount(right.Mask)));
        return caches;
    }

    private static List<L3Info> ReadL3CachesLegacyApi(ulong processMask)
    {
        const int EntrySize64 = 32;
        const int ProcessorMaskOffset = 0;
        const int RelationshipOffset = 8;
        const int CacheLevelOffset = 16;
        const int CacheLineSizeOffset = 18;
        const int CacheSizeOffset = 20;
        const int CacheTypeOffset = 24;

        var caches = new List<L3Info>();
        uint length = 0;
        if (Win32GetLogicalProcessorInformation(IntPtr.Zero, ref length))
        {
            return caches;
        }

        if (Marshal.GetLastWin32Error() != ErrorInsufficientBuffer ||
            length < EntrySize64 ||
            length > 16 * 1024 * 1024 ||
            (length % EntrySize64) != 0)
        {
            return caches;
        }

        var buffer = Marshal.AllocHGlobal(checked((int)length));
        try
        {
            if (!Win32GetLogicalProcessorInformation(buffer, ref length))
            {
                return caches;
            }

            var totalLength = checked((int)length);
            for (var offset = 0; offset + EntrySize64 <= totalLength; offset += EntrySize64)
            {
                var entry = IntPtr.Add(buffer, offset);
                var relationship = Marshal.ReadInt32(entry, RelationshipOffset);
                if (relationship != RelationCache)
                {
                    continue;
                }

                var level = Marshal.ReadByte(entry, CacheLevelOffset);
                var cacheType = Marshal.ReadInt32(entry, CacheTypeOffset);
                if (level != 3 || (cacheType != CacheUnified && cacheType != CacheData))
                {
                    continue;
                }

                var mask = unchecked((ulong)Marshal.ReadInt64(entry, ProcessorMaskOffset)) & processMask;
                if (mask == 0 || caches.Any(cache => cache.Mask == mask))
                {
                    continue;
                }

                var cacheSize = unchecked((uint)Marshal.ReadInt32(entry, CacheSizeOffset));
                var lineSize = unchecked((ushort)Marshal.ReadInt16(entry, CacheLineSizeOffset));
                caches.Add(new L3Info(mask, cacheSize, lineSize));
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }

        caches.Sort((left, right) => BitOperations.TrailingZeroCount(left.Mask).CompareTo(BitOperations.TrailingZeroCount(right.Mask)));
        return caches;
    }

    private static ulong ReadSingleGroupMask(IntPtr entry, int firstGroupAffinityOffset)
    {
        var group = unchecked((ushort)Marshal.ReadInt16(entry, firstGroupAffinityOffset + 8));
        if (group != 0)
        {
            return 0;
        }

        return unchecked((ulong)Marshal.ReadInt64(entry, firstGroupAffinityOffset));
    }

    private static ulong ReadGroupZeroMask(IntPtr entry, ushort groupCount, int firstGroupAffinityOffset)
    {
        ulong mask = 0;
        for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
        {
            var groupAffinityOffset = firstGroupAffinityOffset + (groupIndex * 16);
            var group = unchecked((ushort)Marshal.ReadInt16(entry, groupAffinityOffset + 8));
            if (group != 0)
            {
                continue;
            }

            mask |= unchecked((ulong)Marshal.ReadInt64(entry, groupAffinityOffset));
        }

        return mask;
    }

    private static void WithLogicalProcessorBuffer(
        int relationship,
        Action<IntPtr, int, int> visit)
    {
        uint length = 0;
        if (Win32GetLogicalProcessorInformationEx(relationship, IntPtr.Zero, ref length))
        {
            return;
        }

        if (Marshal.GetLastWin32Error() != ErrorInsufficientBuffer || length < 8 || length > 16 * 1024 * 1024)
        {
            return;
        }

        var buffer = Marshal.AllocHGlobal(checked((int)length));
        try
        {
            if (!Win32GetLogicalProcessorInformationEx(relationship, buffer, ref length))
            {
                return;
            }

            var totalLength = checked((int)length);
            var offset = 0;
            while (offset + 8 <= totalLength)
            {
                var entry = IntPtr.Add(buffer, offset);
                var entryRelationship = Marshal.ReadInt32(entry, 0);
                var entrySize = Marshal.ReadInt32(entry, 4);
                if (entrySize < 8 || offset + entrySize > totalLength)
                {
                    break;
                }

                visit(entry, entryRelationship, entrySize);
                offset += entrySize;
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static ulong ReadCurrentProcessAffinityMask()
    {
        if (!Win32GetProcessAffinityMask(
                Win32GetCurrentProcess(),
                out var processAffinityMask,
                out _))
        {
            return 0;
        }

        return unchecked((ulong)processAffinityMask);
    }

    private static IEnumerable<int> EnumerateBits(ulong mask)
    {
        while (mask != 0)
        {
            var bit = BitOperations.TrailingZeroCount(mask);
            yield return bit;
            mask &= mask - 1;
        }
    }

    private static string NormalizePolicy(string? value)
    {
        var normalized = value?.Trim().ToLowerInvariant();
        return normalized switch
        {
            "legacy" or "off" => "legacy",
            "spread" => "spread",
            "compact" => "compact",
            _ => "auto",
        };
    }

    private static void TraceTopologyOnce(
        Topology topology,
        int[] lanes,
        int reservedHostLanes,
        string policy)
    {
        if (!CacheLogEnabled || System.Threading.Interlocked.Exchange(ref _topologyLogged, 1) != 0)
        {
            return;
        }

        var l3 = topology.L3Caches.Length == 0
            ? "unknown"
            : string.Join(",", topology.L3Caches.Select((cache, index) =>
                $"#{index}:{cache.SizeBytes / (1024 * 1024)}MiB/{BitOperations.PopCount(cache.Mask)}T/line{cache.LineSize}"));
        ulong guestLaneMask = 0;
        foreach (var lane in lanes)
        {
            if ((uint)lane < 64u)
            {
                guestLaneMask |= 1UL << lane;
            }
        }
        var reservedPhysicalCores = topology.Cores.Count(core => (core.Mask & guestLaneMask) == 0);
        var guestL3Domains = topology.Cores
            .Where(core => core.L3Index >= 0 && (core.Mask & guestLaneMask) != 0)
            .Select(core => core.L3Index)
            .Distinct()
            .Count();
        Console.Error.WriteLine(
            $"[CPU-CACHE][INFO] policy={policy} logical={Environment.ProcessorCount} physical={topology.Cores.Length} " +
            $"l3_domains={topology.L3Caches.Length} guest_l3_domains={guestL3Domains} l3_discovery={topology.L3DiscoveryMode} l3_records={topology.L3RecordsSeen} " +
            $"reserved_host_lanes={reservedHostLanes} reserved_physical_cores={reservedPhysicalCores} guest_lane_count={lanes.Length} " +
            $"process_mask=0x{topology.ProcessMask:X} l3=[{l3}] lanes=[{string.Join(",", lanes)}]");
        Console.Error.WriteLine(
            "[CPU-CACHE][INFO] scope=SharpEmu-threads-only; no process affinity, MTRR/PAT, PAGE_NOCACHE, PAGE_WRITECOMBINE, realtime priority or OS-wide cache state changed");
    }

    private sealed record Topology(
        ulong ProcessMask,
        CoreInfo[] Cores,
        L3Info[] L3Caches,
        string L3DiscoveryMode,
        int L3RecordsSeen);
    private readonly record struct CoreInfo(ulong Mask, int PrimaryLogicalProcessor, int L3Index);
    private readonly record struct L3Info(ulong Mask, uint SizeBytes, ushort LineSize);

    [DllImport("kernel32.dll", EntryPoint = "GetLogicalProcessorInformation", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Win32GetLogicalProcessorInformation(
        IntPtr buffer,
        ref uint returnedLength);

    [DllImport("kernel32.dll", EntryPoint = "GetLogicalProcessorInformationEx", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Win32GetLogicalProcessorInformationEx(
        int relationshipType,
        IntPtr buffer,
        ref uint returnedLength);

    [DllImport("kernel32.dll", EntryPoint = "GetCurrentProcess")]
    private static extern nint Win32GetCurrentProcess();

    [DllImport("kernel32.dll", EntryPoint = "GetProcessAffinityMask", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Win32GetProcessAffinityMask(
        nint process,
        out nuint processAffinityMask,
        out nuint systemAffinityMask);
}
