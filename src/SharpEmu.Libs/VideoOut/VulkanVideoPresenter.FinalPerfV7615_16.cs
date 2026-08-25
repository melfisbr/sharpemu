// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Libs.Media;

namespace SharpEmu.Libs.VideoOut;

internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        private static readonly bool _resourceAwareDualQueueV7615 =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC"),
                "0",
                StringComparison.Ordinal);

        private readonly VulkanCrossQueueHazardTrackerV7615 _crossQueueHazardsV7615 = new();
        private readonly List<VulkanQueueAccessV7615> _crossQueueAccessScratchV7615 = new(64);
        private static long _v7615HazardWaitCount;
        private static long _v7615HazardBypassCount;

        private (bool HasTrackedAccess, ulong WaitValue) ResolveCrossQueueWaitV7615(
            bool computeLane,
            IReadOnlyList<TranslatedDrawResources> resources,
            IReadOnlyList<TranslatedDrawResources>? referencedResources)
        {
            if (!_resourceAwareDualQueueV7615)
            {
                return (false, 0);
            }

            BuildCrossQueueAccessesV7615(resources, referencedResources, null, false);
            if (_crossQueueAccessScratchV7615.Count == 0)
            {
                return (false, 0);
            }

            var wait = _crossQueueHazardsV7615.ResolveWait(
                computeLane,
                _crossQueueAccessScratchV7615);
            if (wait != 0)
            {
                Interlocked.Increment(ref _v7615HazardWaitCount);
            }
            else
            {
                Interlocked.Increment(ref _v7615HazardBypassCount);
            }
            return (true, wait);
        }

        private void CommitCrossQueueAccessV7615(
            bool computeLane,
            ulong signalValue,
            IReadOnlyList<TranslatedDrawResources> resources,
            IReadOnlyList<TranslatedDrawResources>? referencedResources)
        {
            if (!_resourceAwareDualQueueV7615 || signalValue == 0)
            {
                return;
            }

            BuildCrossQueueAccessesV7615(resources, referencedResources, null, false);
            _crossQueueHazardsV7615.Commit(
                computeLane,
                signalValue,
                _crossQueueAccessScratchV7615);
        }

        private (bool HasTrackedAccess, ulong WaitValue) ResolvePresentCrossQueueWaitV7615(
            TranslatedDrawResources? resources,
            GuestImageResource? presentedGuestImage)
        {
            if (!_resourceAwareDualQueueV7615)
            {
                return (false, 0);
            }

            _crossQueueAccessScratchV7615.Clear();
            if (resources is not null)
            {
                AppendCrossQueueResourceAccessesV7615(resources);
            }
            if (presentedGuestImage is { Address: not 0 } image)
            {
                _crossQueueAccessScratchV7615.Add(
                    new VulkanQueueAccessV7615(image.Address, false));
            }
            if (_crossQueueAccessScratchV7615.Count == 0)
            {
                return (false, 0);
            }
            return (
                true,
                _crossQueueHazardsV7615.ResolveWait(
                    computeLane: false,
                    _crossQueueAccessScratchV7615));
        }

        private void CommitPresentCrossQueueAccessV7615(
            ulong signalValue,
            TranslatedDrawResources? resources,
            GuestImageResource? presentedGuestImage)
        {
            if (!_resourceAwareDualQueueV7615 || signalValue == 0)
            {
                return;
            }

            _crossQueueAccessScratchV7615.Clear();
            if (resources is not null)
            {
                AppendCrossQueueResourceAccessesV7615(resources);
            }
            if (presentedGuestImage is { Address: not 0 } image)
            {
                _crossQueueAccessScratchV7615.Add(
                    new VulkanQueueAccessV7615(image.Address, false));
            }
            _crossQueueHazardsV7615.Commit(
                computeLane: false,
                signalValue,
                _crossQueueAccessScratchV7615);
        }

        private void BuildCrossQueueAccessesV7615(
            IReadOnlyList<TranslatedDrawResources> resources,
            IReadOnlyList<TranslatedDrawResources>? referencedResources,
            GuestImageResource? extraReadImage,
            bool extraWrite)
        {
            _crossQueueAccessScratchV7615.Clear();
            var source = referencedResources ?? resources;
            foreach (var resource in source)
            {
                AppendCrossQueueResourceAccessesV7615(resource);
            }

            if (extraReadImage is { Address: not 0 } image)
            {
                _crossQueueAccessScratchV7615.Add(
                    new VulkanQueueAccessV7615(image.Address, extraWrite));
            }
        }

        private void AppendCrossQueueResourceAccessesV7615(
            TranslatedDrawResources resource)
        {
            foreach (var global in resource.GlobalMemoryBuffers)
            {
                if (global.BaseAddress != 0)
                {
                    _crossQueueAccessScratchV7615.Add(
                        new VulkanQueueAccessV7615(global.BaseAddress, global.Writable));
                }
            }

            foreach (var texture in resource.Textures)
            {
                if (texture is not null && texture.Address != 0)
                {
                    _crossQueueAccessScratchV7615.Add(
                        new VulkanQueueAccessV7615(texture.Address, texture.IsStorage));
                }
            }

            foreach (var vertex in resource.VertexBuffers)
            {
                if (vertex.Location != 0)
                {
                    _crossQueueAccessScratchV7615.Add(
                        new VulkanQueueAccessV7615(vertex.Location, false));
                }
            }

            foreach (var image in resource.QueueHazardImagesV7615)
            {
                if (image is not null && image.Address != 0)
                {
                    _crossQueueAccessScratchV7615.Add(
                        new VulkanQueueAccessV7615(image.Address, true));
                }
            }
        }
    }
}
