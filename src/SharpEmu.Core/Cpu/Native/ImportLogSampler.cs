// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Generic;

namespace SharpEmu.Core.Cpu.Native;

/// <summary>
/// Bounded diagnostic sampler for repeated import results. The hot key is a
/// value tuple, avoiding the per-dispatch nid + "\0" + result allocation.
/// </summary>
internal sealed class ImportLogSampler
{
    private const long HeadOccurrences = 8;
    private const long SamplePeriod = 10_000;

    private readonly object _gate = new();
    private readonly Dictionary<(string Nid, int Result), long> _counts = new();

    public bool ShouldLog(string nid, int result)
    {
        long count;
        lock (_gate)
        {
            var key = (nid, result);
            _counts.TryGetValue(key, out count);
            count++;
            _counts[key] = count;
        }

        return count <= HeadOccurrences || count % SamplePeriod == 0;
    }

    public void Reset()
    {
        lock (_gate)
        {
            _counts.Clear();
        }
    }
}
