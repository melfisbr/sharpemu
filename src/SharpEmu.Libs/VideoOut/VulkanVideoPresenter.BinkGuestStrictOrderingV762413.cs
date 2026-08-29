// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Libs.Media;
using System.Threading;

namespace SharpEmu.Libs.VideoOut;

internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        private static long _v762413StrictCrossLaneWaitCount;
        private static long _v76383StrictResourceBypassCount;
        private static long _v76383StrictResourceWaitCount;

        private static readonly bool _binkStrictResourceScopeV76383 =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE"),
                "0",
                StringComparison.Ordinal);

        // V76.2.4.13: UseStrictGpuOrdering previously disabled batching but did
        // not make the two physical Vulkan queues strict. If the resource-aware
        // hazard tracker returned HasTrackedAccess=true/WaitValue=0, a physical
        // compute<->graphics lane switch could be submitted with wait=0. During
        // guest Bink decode that lets dependent stages overlap when a descriptor
        // alias or implicit ordering edge is not represented exactly in the
        // resource set. Keep normal dual-queue parallelism outside Bink, but while
        // guest-owned Bink strict mode is active, serialize every physical lane
        // switch against the last signal from the opposite lane.
        private ulong ApplyGuestBinkStrictCrossLaneOrderV762413(
            bool computeLane,
            bool physicalLaneSwitch,
            ulong resourceWaitValue,
            bool hadTrackedAccess)
        {
            if (!physicalLaneSwitch ||
                !BinkGuestOwnedRuntimeV7600.UseStrictGpuOrdering)
            {
                return resourceWaitValue;
            }

            var laneOrderWait = computeLane
                ? _graphicsQueueSignalValueV1131
                : _computeQueueSignalValueV1131;

            // V76.3.8.3: byte-range alias tracking now carries explicit utility
            // image accesses too.  Strict Bink ordering therefore keeps only a
            // proven producer/consumer wait.  A plain physical lane alternation
            // is not a guest dependency.  Explicit recovery can restore V762413
            // with SHARPEMU_BINK_STRICT_RESOURCE_SCOPE=0.
            if (_binkStrictResourceScopeV76383 && _resourceAwareDualQueueV7615)
            {
                var resourceCount = resourceWaitValue != 0
                    ? Interlocked.Increment(ref _v76383StrictResourceWaitCount)
                    : Interlocked.Increment(ref _v76383StrictResourceBypassCount);
                if (resourceCount <= 64 || (resourceCount & (resourceCount - 1)) == 0)
                {
                    Console.Error.WriteLine(
                        "[BINK-GUEST][V76.3.8.3][STRICT-RESOURCE-ORDER] " +
                        $"count={resourceCount} lane={(computeLane ? "compute" : "graphics")} " +
                        $"resource_wait={resourceWaitValue} lane_wait={laneOrderWait} " +
                        $"tracked={(hadTrackedAccess ? 1 : 0)} " +
                        $"action={(resourceWaitValue != 0 ? "wait-real-hazard" : "parallel-no-hazard")}");
                }
                return resourceWaitValue;
            }

            var strictWait = Math.Max(resourceWaitValue, laneOrderWait);
            var count = Interlocked.Increment(
                ref _v762413StrictCrossLaneWaitCount);
            if (count <= 64 || (count & (count - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[BINK-GUEST][V76.2.4.13][STRICT-DUAL-QUEUE] " +
                    $"count={count} lane={(computeLane ? "compute" : "graphics")} " +
                    $"resource_wait={resourceWaitValue} lane_wait={laneOrderWait} " +
                    $"wait={strictWait} tracked={(hadTrackedAccess ? 1 : 0)} " +
                    "action=serialize-cross-lane-recovery");
            }

            return strictWait;
        }
    }
}
