// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;

namespace SharpEmu.Libs.Agc;

/// <summary>
/// Holds DCBs whose parsing was suspended on an unsatisfied WAIT_REG_MEM
/// condition. AgcExports re-checks every waiter against guest memory on each
/// submit and resumes the ones whose condition became true (labels are advanced
/// by ReleaseMem / WriteData / DmaData packets, or by direct CPU writes).
///
/// This preserves cross-submit ordering: the work that follows a wait inside a
/// DCB is only queued once the awaited completion label is genuinely written,
/// instead of being force-satisfied at parse time and running ahead of the
/// compute/graphics work it depends on (which produced a black composite).
/// </summary>
internal static class GpuWaitRegistry
{
    public struct WaitingDcb
    {
        public ulong CommandBufferAddress;
        public ulong ResumeAddress;
        public uint TotalDwords;
        public uint ResumeOffset;
        public ulong WaitAddress;
        public ulong ReferenceValue;
        public ulong Mask;
        public uint CompareFunction;
        public uint ControlValue;
        public bool Is64Bit;
        public bool IsStandard;
        public object? Memory;
        public string? QueueName;
        public ulong SubmissionId;
        // Stopwatch timestamp captured at registration. Stale waiters remain
        // registered; this only controls one-shot diagnostics.
        public long RegisteredTicks;
        public bool StaleReported;
        public object? State;
        // Latched by LatchSatisfiedByValue when a producer wrote a value that
        // satisfies this waiter. The label is frequently reused (reset to 0 for
        // the next frame) immediately after the producing write, so re-reading
        // guest memory at wake time can miss the transient satisfied window.
        // Latching records satisfaction at the moment of the write instead.
        public bool Latched;
        // V54: production sequence already present when this logical wait was
        // first registered. Older history belongs to a recycled-label generation.
        public long ProducedSequenceAtRegistration;
        // Non-zero for indirect-dispatch dimension retries: a bounded deadline
        // (Stopwatch ticks) after which the waiter is resumed even if unsatisfied,
        // so a legitimately empty indirect dispatch can never stall forever.
        public long RetryDeadlineTicks;
    }

    private static readonly object _gate = new();
    private static readonly Dictionary<ulong, List<WaitingDcb>> _waiters = new();
    // Soft bound on suspended waiters. Producerless waits never expire through the
    // normal drain paths, so long boot storms must not grow this table without bound.
    private const int MaxRegisteredWaiters = 4096;
    // The last value each label producer wrote. Used only by the deadlock
    // breaker: our serial submission parser cannot model two GPU queues running
    // concurrently, so a label written -> reset -> re-waited across queues can
    // cycle forever even though a real producer did signal it. Keyed by (memory,
    // address) so distinct guest processes never alias.
    private readonly record struct ProducedLabelValue(ulong Value, long Sequence);
    private static readonly Dictionary<(object, ulong), ProducedLabelValue> _lastProduced = new();
    private static long _producedSequence;
    private static int _waiterCount;

    // Per-thread CPU-memory decorators can wrap the same guest address space.
    // Synchronization registries must key by the shared root, otherwise a wait
    // registered on one native worker is invisible to a producer on another.
    private static object? Canonicalize(object? memory)
    {
        while (memory is SharpEmu.HLE.ICpuMemoryWrapper wrapper)
        {
            memory = wrapper.Inner;
        }

        return memory;
    }

    public static int Count
    {
        get
        {
            lock (_gate)
            {
                return _waiterCount;
            }
        }
    }

    public static int CountForMemory(object memory)
    {
        memory = Canonicalize(memory)!;
        lock (_gate)
        {
            var total = 0;
            foreach (var (_, list) in _waiters)
            {
                foreach (var waiter in list)
                {
                    total += ReferenceEquals(waiter.Memory, memory) ? 1 : 0;
                }
            }

            return total;
        }
    }

    public readonly record struct OutstandingSnapshot(
        int Outstanding,
        int Latched,
        long OldestAgeMs,
        ulong SampleWaitAddress,
        string? SampleQueueName);


    /// <summary>
    /// A label address currently watched by one or more suspended DCBs.
    /// Is64Bit is true when at least one matching waiter consumes eight bytes.
    /// </summary>
    public readonly record struct WatchedLabelSnapshot(
        ulong Address,
        bool Is64Bit,
        int Count);

    /// <summary>
    /// Diagnostics snapshot of suspended WAIT_REG_MEM / dims waiters.
    /// </summary>
    public static OutstandingSnapshot SnapshotOutstanding(object? memory = null)
    {
        memory = Canonicalize(memory);
        lock (_gate)
        {
            var outstanding = 0;
            var latched = 0;
            var oldestTicks = long.MaxValue;
            ulong sampleAddress = 0;
            string? sampleQueue = null;
            var now = Stopwatch.GetTimestamp();
            foreach (var (_, list) in _waiters)
            {
                foreach (var waiter in list)
                {
                    if (memory is not null &&
                        !ReferenceEquals(waiter.Memory, memory))
                    {
                        continue;
                    }

                    outstanding++;
                    if (waiter.Latched)
                    {
                        latched++;
                    }

                    if (waiter.RegisteredTicks != 0 &&
                        waiter.RegisteredTicks < oldestTicks)
                    {
                        oldestTicks = waiter.RegisteredTicks;
                        sampleAddress = waiter.WaitAddress;
                        sampleQueue = waiter.QueueName;
                    }
                }
            }

            var oldestAgeMs = oldestTicks == long.MaxValue || oldestTicks == 0
                ? 0L
                : (now - oldestTicks) * 1000L / Stopwatch.Frequency;
            return new OutstandingSnapshot(
                outstanding,
                latched,
                oldestAgeMs,
                sampleAddress,
                sampleQueue);
        }
    }

    // V23: canonical wait-registry identity and exact compare semantics.
    // V54: generation-aware registration for recycled GPU labels.
    public static void Register(ulong address, WaitingDcb waiter)
    {
        waiter.WaitAddress = address;
        waiter.Memory = Canonicalize(waiter.Memory);
        lock (_gate)
        {
            // V61.23.5: V61.23.1 eager epoch deletion removed; preserve producer history until a real producer updates it.
            if (!_waiters.TryGetValue(address, out var list))
            {
                list = new List<WaitingDcb>();
                _waiters.Add(address, list);
            }

            for (var i = list.Count - 1; i >= 0; i--)
            {
                var existing = list[i];
                if (ReferenceEquals(existing.Memory, waiter.Memory) &&
                    ReferenceEquals(existing.State, waiter.State) &&
                    existing.SubmissionId == waiter.SubmissionId &&
                    existing.ResumeAddress == waiter.ResumeAddress &&
                    existing.ResumeOffset == waiter.ResumeOffset &&
                    string.Equals(existing.QueueName, waiter.QueueName, StringComparison.Ordinal))
                {
                    waiter.ProducedSequenceAtRegistration = existing.ProducedSequenceAtRegistration;
                    waiter.Latched |= existing.Latched;
                    waiter.StaleReported |= existing.StaleReported;
                    if (existing.RegisteredTicks != 0)
                    {
                        waiter.RegisteredTicks = existing.RegisteredTicks;
                    }
                    list[i] = waiter;
                    return;
                }
            }

            waiter.ProducedSequenceAtRegistration =
                _lastProduced.TryGetValue((waiter.Memory!, address), out var producedAtRegistration)
                    ? producedAtRegistration.Sequence
                    : _producedSequence;

            list.Add(waiter);
            _waiterCount++;
            if (_waiterCount > MaxRegisteredWaiters)
            {
                PruneOrphanedWaitersLocked(MaxRegisteredWaiters);
            }
        }
    }

    /// <summary>
    /// Re-evaluates every registered waiter. <paramref name="readValue"/>
    /// receives (address, is64Bit) and returns null when the memory is
    /// unreadable; such waiters are kept registered. Returns the waiters whose
    /// condition is now satisfied (removed from the registry), or null.
    /// </summary>
    public static List<WaitingDcb>? CollectSatisfied(
        object memory,
        Func<ulong, bool, ulong?> readValue)
    {
        memory = Canonicalize(memory)!;
        List<WaitingDcb>? woken = null;
        lock (_gate)
        {
            List<ulong>? emptied = null;
            foreach (var (address, list) in _waiters)
            {
                for (var i = list.Count - 1; i >= 0; i--)
                {
                    if (!ReferenceEquals(list[i].Memory, memory))
                    {
                        continue;
                    }

                    var satisfied = list[i].Latched;
                    if (!satisfied)
                    {
                        var value = readValue(address, list[i].Is64Bit);
                        satisfied = value is not null && Compare(list[i], value.Value);
                    }

                    if (!satisfied)
                    {
                        continue;
                    }

                    woken ??= new List<WaitingDcb>();
                    woken.Add(list[i]);
                    RemoveWaiterAtLocked(list, i);
                }

                if (list.Count == 0)
                {
                    emptied ??= new List<ulong>();
                    emptied.Add(address);
                }
            }

            if (emptied is not null)
            {
                foreach (var address in emptied)
                {
                    _waiters.Remove(address);
                }
            }
        }

        return woken;
    }

    /// <summary>
    /// Returns waiters that have remained unsatisfied longer than
    /// <paramref name="maxAgeTicks"/> exactly once, without removing them or
    /// changing their labels. Missing GPU work must fail closed: advancing a
    /// command buffer without its real producer corrupts cross-queue ordering.
    /// </summary>
    public static List<WaitingDcb>? CollectUnreportedStale(
        object memory,
        long nowTicks,
        long maxAgeTicks)
    {
        memory = Canonicalize(memory)!;
        List<WaitingDcb>? stale = null;
        lock (_gate)
        {
            foreach (var (_, list) in _waiters)
            {
                for (var i = list.Count - 1; i >= 0; i--)
                {
                    var waiter = list[i];
                    if (!ReferenceEquals(waiter.Memory, memory) ||
                        waiter.StaleReported ||
                        nowTicks - waiter.RegisteredTicks < maxAgeTicks)
                    {
                        continue;
                    }

                    stale ??= new List<WaitingDcb>();
                    waiter.StaleReported = true;
                    list[i] = waiter;
                    stale.Add(waiter);
                }
            }
        }

        return stale;
    }

    /// <summary>
    /// Returns watched labels overlapped by a newly discovered producer. Used
    /// only for diagnostics; producer completion still wakes through the
    /// normal CollectSatisfied path after the ordered memory write executes.
    /// </summary>
    public static List<(ulong Address, int Count)> SnapshotInRange(
        object memory,
        ulong start,
        ulong length)
    {
        memory = Canonicalize(memory)!;
        var matches = new List<(ulong Address, int Count)>();
        if (length == 0)
        {
            return matches;
        }

        var end = start > ulong.MaxValue - length ? ulong.MaxValue : start + length;
        lock (_gate)
        {
            foreach (var (address, list) in _waiters)
            {
                var matchingCount = 0;
                var any64Bit = false;
                foreach (var waiter in list)
                {
                    if (!ReferenceEquals(waiter.Memory, memory))
                    {
                        continue;
                    }

                    matchingCount++;
                    any64Bit |= waiter.Is64Bit;
                }

                if (matchingCount == 0)
                {
                    continue;
                }

                var width = any64Bit
                    ? sizeof(ulong)
                    : sizeof(uint);
                var waitEnd = address > ulong.MaxValue - (ulong)width
                    ? ulong.MaxValue
                    : address + (ulong)width;
                if (start < waitEnd && address < end)
                {
                    matches.Add((address, matchingCount));
                }
            }
        }

        return matches;
    }

    /// <summary>
    /// Returns watched labels overlapped by a producer range, including the
    /// widest access required at each address. This is used after DMA/WRITE_DATA
    /// completes so the exact value written to every relevant label can be
    /// recorded without scanning or reading the entire producer range.
    /// </summary>
    public static List<WatchedLabelSnapshot> SnapshotWatchedLabelsInRange(
        object memory,
        ulong start,
        ulong length)
    {
        memory = Canonicalize(memory)!;
        var matches = new List<WatchedLabelSnapshot>();
        if (length == 0)
        {
            return matches;
        }

        var end = start > ulong.MaxValue - length
            ? ulong.MaxValue
            : start + length;

        lock (_gate)
        {
            foreach (var (address, list) in _waiters)
            {
                var matchingCount = 0;
                var any64Bit = false;
                foreach (var waiter in list)
                {
                    if (!ReferenceEquals(waiter.Memory, memory))
                    {
                        continue;
                    }

                    matchingCount++;
                    any64Bit |= waiter.Is64Bit;
                }

                if (matchingCount == 0)
                {
                    continue;
                }

                var width = any64Bit
                    ? (ulong)sizeof(ulong)
                    : sizeof(uint);
                var waitEnd = address > ulong.MaxValue - width
                    ? ulong.MaxValue
                    : address + width;

                if (start < waitEnd && address < end)
                {
                    matches.Add(new WatchedLabelSnapshot(
                        address,
                        any64Bit,
                        matchingCount));
                }
            }
        }

        return matches;
    }

    /// <summary>
    /// Records satisfaction for every waiter at <paramref name="address"/> whose
    /// condition is met by <paramref name="value"/> — the value a producer just
    /// wrote to that label. Called from the ordered producer side effect so a
    /// same-frame label reset cannot lose the wakeup. The waiters stay registered
    /// (latched) and are drained by the next CollectSatisfied. Returns true when
    /// at least one waiter latched, so the caller can trigger a wake pass.
    /// </summary>
    public static bool LatchSatisfiedByValue(object memory, ulong address, ulong value)
    {
        memory = Canonicalize(memory)!;
        lock (_gate)
        {
            return LatchSatisfiedByValueLocked(memory, address, value);
        }
    }

    private static bool LatchSatisfiedByValueLocked(
        object memory,
        ulong address,
        ulong value)
    {
        if (!_waiters.TryGetValue(address, out var list))
        {
            return false;
        }

        var latchedAny = false;
        for (var i = 0; i < list.Count; i++)
        {
            var waiter = list[i];
            if (waiter.Latched ||
                !ReferenceEquals(waiter.Memory, memory) ||
                !Compare(waiter, value))
            {
                continue;
            }

            waiter.Latched = true;
            list[i] = waiter;
            latchedAny = true;
        }

        return latchedAny;
    }

    /// <summary>
    /// Removes and returns waiters carrying a <see cref="WaitingDcb.RetryDeadlineTicks"/>
    /// that has elapsed. Used for indirect-dispatch dimension retries: the caller
    /// resumes them so a genuinely empty dispatch (dims that never become non-zero)
    /// is dropped after a bounded wait instead of stalling the queue forever.
    /// </summary>
    public static List<WaitingDcb>? CollectExpiredRetries(object memory, long nowTicks)
    {
        memory = Canonicalize(memory)!;
        List<WaitingDcb>? expired = null;
        lock (_gate)
        {
            List<ulong>? emptied = null;
            foreach (var (address, list) in _waiters)
            {
                for (var i = list.Count - 1; i >= 0; i--)
                {
                    var waiter = list[i];
                    if (waiter.RetryDeadlineTicks == 0 ||
                        !ReferenceEquals(waiter.Memory, memory) ||
                        nowTicks < waiter.RetryDeadlineTicks)
                    {
                        continue;
                    }

                    expired ??= new List<WaitingDcb>();
                    expired.Add(waiter);
                    RemoveWaiterAtLocked(list, i);
                }

                if (list.Count == 0)
                {
                    emptied ??= new List<ulong>();
                    emptied.Add(address);
                }
            }

            if (emptied is not null)
            {
                foreach (var address in emptied)
                {
                    _waiters.Remove(address);
                }
            }
        }

        return expired;
    }

    /// <summary>
    /// Updates the bounded retry deadline for a specific suspended packet.
    /// Indirect-dispatch waits use this after an ordered GPU-visibility probe:
    /// the initial deadline protects against a renderer that never reaches the
    /// probe, while a short post-visibility grace period handles genuinely empty
    /// dispatches without racing first-use shader compilation.
    /// </summary>
    public static bool UpdateRetryDeadline(
        object memory,
        ulong waitAddress,
        ulong resumeAddress,
        long retryDeadlineTicks)
    {
        memory = Canonicalize(memory)!;
        lock (_gate)
        {
            if (!_waiters.TryGetValue(waitAddress, out var list))
            {
                return false;
            }

            var updated = false;
            for (var index = 0; index < list.Count; index++)
            {
                var waiter = list[index];
                if (waiter.RetryDeadlineTicks == 0 ||
                    !ReferenceEquals(waiter.Memory, memory) ||
                    waiter.ResumeAddress != resumeAddress)
                {
                    continue;
                }

                waiter.RetryDeadlineTicks = retryDeadlineTicks;
                list[index] = waiter;
                updated = true;
            }

            return updated;
        }
    }

    public static List<WaitingDcb>? CollectAllForMemory(object memory)
    {
        memory = Canonicalize(memory)!;
        List<WaitingDcb>? collected = null;
        lock (_gate)
        {
            List<ulong>? emptied = null;
            foreach (var (address, list) in _waiters)
            {
                for (var index = list.Count - 1; index >= 0; index--)
                {
                    if (!ReferenceEquals(list[index].Memory, memory))
                    {
                        continue;
                    }

                    collected ??= new List<WaitingDcb>();
                    collected.Add(list[index]);
                    RemoveWaiterAtLocked(list, index);
                }

                if (list.Count == 0)
                {
                    emptied ??= new List<ulong>();
                    emptied.Add(address);
                }
            }

            if (emptied is not null)
            {
                foreach (var address in emptied)
                {
                    _waiters.Remove(address);
                }
            }
        }

        return collected;
    }

    /// <summary>
    /// Drops produced-label values that no registered waiter is watching. Called
    /// under <see cref="_gate"/> when the table reaches its soft bound. A value
    /// still watched by a waiter is the only thing that can release that waiter
    /// once the guest recycles its label, so those are always retained even if
    /// the table has to grow past the bound.
    /// </summary>
    private static void PruneUnwatchedProducedLocked()
    {
        List<(object Memory, ulong Address)>? unwatched = null;
        foreach (var (key, _) in _lastProduced)
        {
            if (_waiters.TryGetValue(key.Item2, out var list))
            {
                var watched = false;
                foreach (var waiter in list)
                {
                    if (ReferenceEquals(waiter.Memory, key.Item1))
                    {
                        watched = true;
                        break;
                    }
                }

                if (watched)
                {
                    continue;
                }
            }

            (unwatched ??= []).Add(key);
        }

        if (unwatched is null)
        {
            return;
        }

        foreach (var key in unwatched)
        {
            _lastProduced.Remove(key);
        }
    }

    /// <summary>Drops the oldest waiters until at most <paramref name="keepAtMost"/> remain, preferring producerless orphans.</summary>
    private static void PruneOrphanedWaitersLocked(int keepAtMost)
    {
        if (_waiterCount <= keepAtMost)
        {
            return;
        }

        DropOldestWaitersLocked(keepAtMost, orphansOnly: true);
        if (_waiterCount > keepAtMost)
        {
            DropOldestWaitersLocked(keepAtMost, orphansOnly: false);
        }
    }

    private static void DropOldestWaitersLocked(int keepAtMost, bool orphansOnly)
    {
        if (_waiterCount <= keepAtMost)
        {
            return;
        }

        var candidates = new List<(ulong Address, int Index, long RegisteredTicks)>(_waiterCount);
        foreach (var (address, list) in _waiters)
        {
            for (var i = 0; i < list.Count; i++)
            {
                var waiter = list[i];
                if (orphansOnly &&
                    (waiter.Latched ||
                     waiter.RetryDeadlineTicks != 0 ||
                     (waiter.Memory is not null && _lastProduced.ContainsKey((waiter.Memory, address)))))
                {
                    continue;
                }
                candidates.Add((address, i, waiter.RegisteredTicks));
            }
        }

        if (candidates.Count == 0)
        {
            return;
        }

        candidates.Sort(static (left, right) => left.RegisteredTicks.CompareTo(right.RegisteredTicks));
        var toDrop = Math.Min(candidates.Count, _waiterCount - keepAtMost);
        var dropSet = candidates.GetRange(0, toDrop);
        dropSet.Sort(static (left, right) =>
        {
            var addressCompare = left.Address.CompareTo(right.Address);
            return addressCompare != 0 ? addressCompare : right.Index.CompareTo(left.Index);
        });

        List<ulong>? emptied = null;
        foreach (var (address, index, _) in dropSet)
        {
            if (!_waiters.TryGetValue(address, out var list) || index < 0 || index >= list.Count)
            {
                continue;
            }
            RemoveWaiterAtLocked(list, index);
            if (list.Count == 0)
            {
                emptied ??= new List<ulong>();
                emptied.Add(address);
            }
        }

        if (emptied is not null)
        {
            foreach (var address in emptied)
            {
                _waiters.Remove(address);
            }
        }
    }

    private static void RemoveWaiterAtLocked(List<WaitingDcb> list, int index)
    {
        list.RemoveAt(index);
        if (_waiterCount > 0)
        {
            _waiterCount--;
        }
    }

    /// <summary>Records the value a label producer wrote, for the deadlock
    /// breaker. Also latches any already-waiting waiter it satisfies.</summary>
    public static bool TryGetLastProduced(
        object memory,
        ulong address,
        out ulong value)
    {
        memory = Canonicalize(memory)!;
        lock (_gate)
        {
            if (_lastProduced.TryGetValue((memory, address), out var produced))
            {
                value = produced.Value;
                return true;
            }
            value = 0;
            return false;
        }
    }

    /// <summary>Records the value a label producer wrote, for the deadlock
    /// breaker. Also latches any already-waiting waiter it satisfies.</summary>
    public static bool RecordProduced(object memory, ulong address, ulong value)
    {
        memory = Canonicalize(memory)!;
        lock (_gate)
        {
            if (_lastProduced.Count >= 8192)
            {
                // These entries are release state, not a cache. CollectDeadlockBroken
                // can only free a waiter whose label the guest has since recycled by
                // replaying the value a real producer wrote to it, so clearing the
                // table wholesale strands every such waiter forever — the suspended
                // queue then never resumes and the title wedges with its render
                // thread parked. Drop only values no live waiter is watching, and
                // let the table exceed the bound when they all are.
                PruneUnwatchedProducedLocked();
            }

            var sequence = ++_producedSequence;
            _lastProduced[(memory, address)] =
                new ProducedLabelValue(value, sequence);

            // Updating the producer history and latching waiters must be one
            // atomic operation. Previously Register() could insert a new waiter
            // between these two steps, allowing a producer that completed before
            // the wait was issued to satisfy it accidentally.
            return LatchSatisfiedByValueLocked(memory, address, value);
        }
    }

    /// <summary>
    /// Legacy age-gated fallback retained for safety. V55 normally consumes
    /// post-registration produced evidence through
    /// CollectProducedSatisfiedAfterRegistration before this method is reached.
    /// </summary>
    // V54: V53 queue-cycle shortcut removed. The V53 capture showed
    // 113/113 detected cycles were cycle_length=1 self-queue cases.

    // V55: normal generation-aware produced wake.
    // A producer value written after the waiter was registered is not a
    // deadlock heuristic; it is direct synchronization evidence. Collect it
    // immediately even when guest memory has already recycled the label.
    public static List<WaitingDcb>? CollectProducedSatisfiedAfterRegistration(
        object memory)
    {
        memory = Canonicalize(memory)!;
        List<WaitingDcb>? satisfied = null;
        lock (_gate)
        {
            List<ulong>? emptied = null;
            foreach (var (address, list) in _waiters)
            {
                for (var index = list.Count - 1; index >= 0; index--)
                {
                    var waiter = list[index];
                    if (!ReferenceEquals(waiter.Memory, memory) ||
                        !_lastProduced.TryGetValue((memory, address), out var produced) ||
                        produced.Sequence <= waiter.ProducedSequenceAtRegistration ||
                        !Compare(waiter, produced.Value))
                    {
                        continue;
                    }

                    satisfied ??= new List<WaitingDcb>();
                    satisfied.Add(waiter);
                    RemoveWaiterAtLocked(list, index);
                }

                if (list.Count == 0)
                {
                    emptied ??= new List<ulong>();
                    emptied.Add(address);
                }
            }

            if (emptied is not null)
            {
                foreach (var address in emptied)
                {
                    _waiters.Remove(address);
                }
            }
        }

        return satisfied;
    }

    public static List<WaitingDcb>? CollectDeadlockBroken(
        object memory,
        long nowTicks,
        long minAgeTicks)
    {
        memory = Canonicalize(memory)!;
        List<WaitingDcb>? broken = null;
        lock (_gate)
        {
            List<ulong>? emptied = null;
            foreach (var (address, list) in _waiters)
            {
                for (var i = list.Count - 1; i >= 0; i--)
                {
                    var waiter = list[i];
                    if (!ReferenceEquals(waiter.Memory, memory) ||
                        nowTicks - waiter.RegisteredTicks < minAgeTicks ||
                        !_lastProduced.TryGetValue((memory, address), out var produced) ||
                        produced.Sequence <= waiter.ProducedSequenceAtRegistration ||
                        !Compare(waiter, produced.Value))
                    {
                        continue;
                    }

                    broken ??= new List<WaitingDcb>();
                    broken.Add(waiter);
                    RemoveWaiterAtLocked(list, i);
                }

                if (list.Count == 0)
                {
                    emptied ??= new List<ulong>();
                    emptied.Add(address);
                }
            }

            if (emptied is not null)
            {
                foreach (var address in emptied)
                {
                    _waiters.Remove(address);
                }
            }
        }

        return broken;
    }

    public static bool Compare(in WaitingDcb waiter, ulong value)
    {
        var masked = value & waiter.Mask;
        var reference = waiter.ReferenceValue & waiter.Mask;
        return waiter.CompareFunction switch
        {
            0 => true,
            1 => masked < reference,
            2 => masked <= reference,
            3 => masked == reference,
            4 => masked != reference,
            5 => masked >= reference,
            6 => masked > reference,
            _ => true,
        };
    }

    public static void Clear()
    {
        lock (_gate)
        {
            _waiters.Clear();
            _lastProduced.Clear();
            _producedSequence = 0;
            _waiterCount = 0;
        }
    }
}
