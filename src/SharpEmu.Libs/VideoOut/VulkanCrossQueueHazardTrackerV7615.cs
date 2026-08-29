// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Libs.VideoOut;

// V76.0.26: hazards are guest byte ranges, not only exact base addresses.
// Length is normalized to at least one byte by the tracker.
internal readonly record struct VulkanQueueAccessV7615(
    ulong Address,
    ulong Length,
    bool Write);

/// <summary>
/// V76.0.15/V76.0.26 tracks the last graphics/compute access to guest-addressed
/// byte ranges. A read waits only for an opposite-lane writer; a write waits for
/// every opposite-lane access. The map stays sorted/disjoint and splits only at
/// access boundaries, so overlapping aliases no longer miss a hazard merely
/// because their base addresses differ.
/// </summary>
internal sealed class VulkanCrossQueueHazardTrackerV7615
{
    private readonly record struct State(
        ulong GraphicsAccess,
        ulong GraphicsWrite,
        ulong ComputeAccess,
        ulong ComputeWrite);

    private readonly record struct TrackedRange(
        ulong Start,
        ulong EndInclusive,
        State State);

    private readonly List<TrackedRange> _ranges = [];

    internal ulong ResolveWait(
        bool computeLane,
        IReadOnlyList<VulkanQueueAccessV7615> accesses)
    {
        ulong wait = 0;
        for (var accessIndex = 0; accessIndex < accesses.Count; accessIndex++)
        {
            var access = accesses[accessIndex];
            if (!TryNormalize(access, out var start, out var endInclusive))
            {
                continue;
            }

            var rangeIndex = FindFirstEndingAtOrAfter(start);
            for (; rangeIndex < _ranges.Count; rangeIndex++)
            {
                var range = _ranges[rangeIndex];
                if (range.Start > endInclusive)
                {
                    break;
                }

                var state = range.State;
                var candidate = computeLane
                    ? access.Write ? state.GraphicsAccess : state.GraphicsWrite
                    : access.Write ? state.ComputeAccess : state.ComputeWrite;
                wait = Math.Max(wait, candidate);
            }
        }
        return wait;
    }

    internal void Commit(
        bool computeLane,
        ulong signalValue,
        IReadOnlyList<VulkanQueueAccessV7615> accesses)
    {
        if (signalValue == 0)
        {
            return;
        }

        for (var index = 0; index < accesses.Count; index++)
        {
            var access = accesses[index];
            if (!TryNormalize(access, out var start, out var endInclusive))
            {
                continue;
            }

            CommitRange(start, endInclusive, computeLane, access.Write, signalValue);
        }
    }

    private void CommitRange(
        ulong start,
        ulong endInclusive,
        bool computeLane,
        bool write,
        ulong signalValue)
    {
        var first = FindFirstEndingAtOrAfter(start);
        var lastExclusive = first;
        while (lastExclusive < _ranges.Count &&
               _ranges[lastExclusive].Start <= endInclusive)
        {
            lastExclusive++;
        }

        // No prior range overlaps this access. Insert one exact range and merge
        // only equal-state neighbours; no scan of unrelated resources is needed.
        if (first == lastExclusive)
        {
            _ranges.Insert(
                first,
                new TrackedRange(
                    start,
                    endInclusive,
                    UpdateState(default, computeLane, write, signalValue)));
            MergeAround(first);
            return;
        }

        var replacement = new List<TrackedRange>(lastExclusive - first + 4);
        var cursor = start;
        var cursorValid = true;

        for (var index = first; index < lastExclusive; index++)
        {
            var range = _ranges[index];
            if (range.Start < start)
            {
                replacement.Add(new TrackedRange(
                    range.Start,
                    start - 1,
                    range.State));
            }

            var overlapStart = Math.Max(range.Start, start);
            var overlapEnd = Math.Min(range.EndInclusive, endInclusive);

            if (cursorValid && cursor < overlapStart)
            {
                replacement.Add(new TrackedRange(
                    cursor,
                    overlapStart - 1,
                    UpdateState(default, computeLane, write, signalValue)));
            }

            replacement.Add(new TrackedRange(
                overlapStart,
                overlapEnd,
                UpdateState(range.State, computeLane, write, signalValue)));

            if (overlapEnd == ulong.MaxValue)
            {
                cursorValid = false;
            }
            else
            {
                cursor = overlapEnd + 1;
                if (cursor > endInclusive)
                {
                    cursorValid = false;
                }
            }

            if (range.EndInclusive > endInclusive)
            {
                replacement.Add(new TrackedRange(
                    endInclusive + 1,
                    range.EndInclusive,
                    range.State));
            }
        }

        if (cursorValid && cursor <= endInclusive)
        {
            replacement.Add(new TrackedRange(
                cursor,
                endInclusive,
                UpdateState(default, computeLane, write, signalValue)));
        }

        CoalesceAdjacent(replacement);
        _ranges.RemoveRange(first, lastExclusive - first);
        _ranges.InsertRange(first, replacement);
        MergeAround(first);
    }

    private int FindFirstEndingAtOrAfter(ulong address)
    {
        var low = 0;
        var high = _ranges.Count;
        while (low < high)
        {
            var mid = low + ((high - low) >> 1);
            if (_ranges[mid].EndInclusive < address)
            {
                low = mid + 1;
            }
            else
            {
                high = mid;
            }
        }
        return low;
    }

    private void MergeAround(int index)
    {
        if (_ranges.Count < 2)
        {
            return;
        }

        var current = Math.Clamp(index, 0, _ranges.Count - 1);
        if (current > 0 && CanMerge(_ranges[current - 1], _ranges[current]))
        {
            _ranges[current - 1] = Merge(_ranges[current - 1], _ranges[current]);
            _ranges.RemoveAt(current);
            current--;
        }

        while (current + 1 < _ranges.Count &&
               CanMerge(_ranges[current], _ranges[current + 1]))
        {
            _ranges[current] = Merge(_ranges[current], _ranges[current + 1]);
            _ranges.RemoveAt(current + 1);
        }
    }

    private static void CoalesceAdjacent(List<TrackedRange> ranges)
    {
        if (ranges.Count < 2)
        {
            return;
        }

        var write = 0;
        for (var read = 1; read < ranges.Count; read++)
        {
            if (CanMerge(ranges[write], ranges[read]))
            {
                ranges[write] = Merge(ranges[write], ranges[read]);
            }
            else
            {
                write++;
                ranges[write] = ranges[read];
            }
        }
        if (write + 1 < ranges.Count)
        {
            ranges.RemoveRange(write + 1, ranges.Count - write - 1);
        }
    }

    private static bool CanMerge(TrackedRange left, TrackedRange right) =>
        left.EndInclusive != ulong.MaxValue &&
        left.EndInclusive + 1 == right.Start &&
        left.State == right.State;

    private static TrackedRange Merge(TrackedRange left, TrackedRange right) =>
        new(left.Start, right.EndInclusive, left.State);

    private static State UpdateState(
        State state,
        bool computeLane,
        bool write,
        ulong signalValue)
    {
        if (computeLane)
        {
            return state with
            {
                ComputeAccess = Math.Max(state.ComputeAccess, signalValue),
                ComputeWrite = write
                    ? Math.Max(state.ComputeWrite, signalValue)
                    : state.ComputeWrite,
            };
        }

        return state with
        {
            GraphicsAccess = Math.Max(state.GraphicsAccess, signalValue),
            GraphicsWrite = write
                ? Math.Max(state.GraphicsWrite, signalValue)
                : state.GraphicsWrite,
        };
    }

    private static bool TryNormalize(
        VulkanQueueAccessV7615 access,
        out ulong start,
        out ulong endInclusive)
    {
        start = access.Address;
        endInclusive = 0;
        if (start == 0)
        {
            return false;
        }

        var length = Math.Max(access.Length, 1UL);
        var extent = length - 1;
        endInclusive = extent > ulong.MaxValue - start
            ? ulong.MaxValue
            : start + extent;
        return true;
    }
}
