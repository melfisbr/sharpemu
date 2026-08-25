// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers;
using System.Numerics;

namespace SharpEmu.Libs.Gpu;

/// <summary>
/// The pool backing AGC-to-presenter ownership transfers, shared by every backend
/// (the AGC layer rents, the presenter returns, so both sides must use one pool).
/// Guest draw snapshots churn through a small set of 128 KiB-16 MiB size classes
/// thousands of times per second; the process-wide shared pool trims and
/// repartitions those large arrays aggressively under GC load, causing hundreds of
/// MiB/s of replacement byte[] allocations, so this pool is bounded and non-shared.
/// </summary>
internal static class GuestDataPool
{
    // SHARPEMU_V74_0_56_19_MANAGED_ALLOCATION_THROUGHPUT
    // V56.18 measured ~0.7-1.0 GiB of managed allocation every 2 seconds in
    // steady UI, with repeated Gen2 collections. The old pool retained only
    // 64 MiB and four arrays per bucket even though a single guest-work burst
    // can hold hundreds of MiB of 128 KiB-16 MiB shader/vertex/global snapshots.
    //
    // Keep the cross-title defaults unchanged. The V56.19 runner opts into a
    // larger pool on the user's 32 GiB host. This changes host allocation
    // reuse only; guest bytes and ownership semantics are identical.
    private static readonly int ConfiguredMaxArrayLength =
        Math.Clamp(
            ReadPositiveEnvironmentIntV7405619(
                "SHARPEMU_GUEST_DATA_POOL_MAX_ARRAY_MB",
                16),
            1,
            64) * 1024 * 1024;

    private static readonly ulong ConfiguredMaxCachedBytes =
        (ulong)Math.Clamp(
            ReadPositiveEnvironmentIntV7405619(
                "SHARPEMU_GUEST_DATA_POOL_MB",
                64),
            16,
            1024) * 1024UL * 1024UL;

    private static readonly int ConfiguredMaxArraysPerBucket =
        Math.Clamp(
            ReadPositiveEnvironmentIntV7405619(
                "SHARPEMU_GUEST_DATA_POOL_BUCKET",
                4),
            1,
            32);

    private static readonly bool TracePoolV7405619 =
        string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_TRACE_GUEST_DATA_POOL"),
            "1",
            StringComparison.Ordinal);

    private static int ReadPositiveEnvironmentIntV7405619(
        string name,
        int fallback)
    {
        return int.TryParse(
                Environment.GetEnvironmentVariable(name),
                out var value) &&
            value > 0
                ? value
                : fallback;
    }

    public static ArrayPool<byte> Shared { get; } = new BoundedByteArrayPool(
        maxArrayLength: ConfiguredMaxArrayLength,
        maxCachedBytes: ConfiguredMaxCachedBytes,
        maxArraysPerBucket: ConfiguredMaxArraysPerBucket,
        trace: TracePoolV7405619);

    public static void Trim() => ((BoundedByteArrayPool)Shared).Trim();

    /// <summary>
    /// Returns outstanding lease count and idle cached bytes for runtime
    /// diagnostics. A steadily increasing lease count is a strong signal that
    /// a producer path retained pooled guest data without transferring ownership.
    /// </summary>
    public static (int LeaseCount, ulong CachedBytes) DiagnosticStats() =>
        ((BoundedByteArrayPool)Shared).Stats();

    private sealed class BoundedByteArrayPool : ArrayPool<byte>
    {
        private readonly object _gate = new();
        private readonly int _maxArrayLength;
        private readonly ulong _maxCachedBytes;
        private readonly int _maxArraysPerBucket;
        private readonly Dictionary<int, Stack<byte[]>> _cachedByBucket = [];
        private readonly HashSet<byte[]> _leases =
            new(System.Collections.Generic.ReferenceEqualityComparer.Instance);
        private ulong _cachedBytes;
        private readonly bool _trace;
        private long _newArrayCount;
        private long _newArrayBytes;
        private long _reuseCount;
        private long _reuseBytes;

        public BoundedByteArrayPool(
            int maxArrayLength,
            ulong maxCachedBytes,
            int maxArraysPerBucket,
            bool trace)
        {
            ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxArrayLength);
            ArgumentOutOfRangeException.ThrowIfZero(maxCachedBytes);
            ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxArraysPerBucket);
            _maxArrayLength = maxArrayLength;
            _maxCachedBytes = maxCachedBytes;
            _maxArraysPerBucket = maxArraysPerBucket;
            _trace = trace;
        }

        public override byte[] Rent(int minimumLength)
        {
            ArgumentOutOfRangeException.ThrowIfNegative(minimumLength);
            var length = GetAllocationLength(minimumLength);
            byte[]? array = null;
            var reused = false;
            long traceCount;
            long traceBytes;

            lock (_gate)
            {
                if (length <= _maxArrayLength &&
                    _cachedByBucket.TryGetValue(length, out var bucket) &&
                    bucket.TryPop(out array))
                {
                    _cachedBytes -= (ulong)array.LongLength;
                    reused = true;
                }

                if (array is null)
                {
                    array = new byte[length];
                    traceCount = ++_newArrayCount;
                    _newArrayBytes += array.LongLength;
                    traceBytes = _newArrayBytes;
                }
                else
                {
                    traceCount = ++_reuseCount;
                    _reuseBytes += array.LongLength;
                    traceBytes = _reuseBytes;
                }

                _leases.Add(array);
            }

            if (_trace &&
                length >= 128 * 1024 &&
                (traceCount <= 64 ||
                 (traceCount & (traceCount - 1)) == 0))
            {
                var kind = reused ? "reuse" : "alloc";
                Console.Error.WriteLine(
                    $"[V74.0.56.19][GUEST_DATA_POOL] " +
                    $"kind={kind} count={traceCount} " +
                    $"bytes={length} total_mb={traceBytes / (1024 * 1024)} " +
                    $"max_array_mb={_maxArrayLength / (1024 * 1024)} " +
                    $"budget_mb={_maxCachedBytes / (1024 * 1024)} " +
                    $"bucket_limit={_maxArraysPerBucket}");
            }

            return array;
        }

        public override void Return(byte[] array, bool clearArray = false)
        {
            ArgumentNullException.ThrowIfNull(array);
            lock (_gate)
            {
                if (!_leases.Remove(array))
                {
                    return;
                }
            }

            if (clearArray)
            {
                Array.Clear(array);
            }

            lock (_gate)
            {
                if (array.Length > _maxArrayLength ||
                    !IsBucketLength(array.Length) ||
                    (ulong)array.LongLength > _maxCachedBytes -
                        Math.Min(_cachedBytes, _maxCachedBytes))
                {
                    return;
                }

                if (!_cachedByBucket.TryGetValue(array.Length, out var bucket))
                {
                    bucket = new Stack<byte[]>();
                    _cachedByBucket.Add(array.Length, bucket);
                }

                if (bucket.Count >= _maxArraysPerBucket)
                {
                    return;
                }

                bucket.Push(array);
                _cachedBytes += (ulong)array.LongLength;
            }
        }

        public void Trim()
        {
            lock (_gate)
            {
                _cachedByBucket.Clear();
                _cachedBytes = 0;
            }
        }

        public (int LeaseCount, ulong CachedBytes) Stats()
        {
            lock (_gate)
            {
                return (_leases.Count, _cachedBytes);
            }
        }

        private int GetAllocationLength(int minimumLength)
        {
            if (minimumLength <= 16)
            {
                return 16;
            }

            if (minimumLength > _maxArrayLength)
            {
                return minimumLength;
            }

            return checked((int)BitOperations.RoundUpToPowerOf2((uint)minimumLength));
        }

        private static bool IsBucketLength(int length) =>
            length >= 16 && (length & (length - 1)) == 0;
    }
}
