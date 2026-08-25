// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Libs.VideoOut;

internal readonly record struct VulkanQueueAccessV7615(ulong Address, bool Write);

/// <summary>
/// V76.0.15 tracks the last graphics/compute access to guest-addressed
/// resources. A read waits only for an opposite-lane writer; a write waits for
/// every opposite-lane access. Timeline semaphore values remain monotonically
/// increasing per lane and are committed only after a successful queue submit.
/// </summary>
internal sealed class VulkanCrossQueueHazardTrackerV7615
{
    private struct State
    {
        public ulong GraphicsAccess;
        public ulong GraphicsWrite;
        public ulong ComputeAccess;
        public ulong ComputeWrite;
    }

    private readonly Dictionary<ulong, State> _states = [];

    internal ulong ResolveWait(bool computeLane, IReadOnlyList<VulkanQueueAccessV7615> accesses)
    {
        ulong wait = 0;
        for (var index = 0; index < accesses.Count; index++)
        {
            var access = accesses[index];
            if (access.Address == 0 || !_states.TryGetValue(access.Address, out var state))
            {
                continue;
            }

            var candidate = computeLane
                ? access.Write ? state.GraphicsAccess : state.GraphicsWrite
                : access.Write ? state.ComputeAccess : state.ComputeWrite;
            wait = Math.Max(wait, candidate);
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
            if (access.Address == 0)
            {
                continue;
            }

            _states.TryGetValue(access.Address, out var state);
            if (computeLane)
            {
                state.ComputeAccess = Math.Max(state.ComputeAccess, signalValue);
                if (access.Write)
                {
                    state.ComputeWrite = Math.Max(state.ComputeWrite, signalValue);
                }
            }
            else
            {
                state.GraphicsAccess = Math.Max(state.GraphicsAccess, signalValue);
                if (access.Write)
                {
                    state.GraphicsWrite = Math.Max(state.GraphicsWrite, signalValue);
                }
            }
            _states[access.Address] = state;
        }
    }
}
