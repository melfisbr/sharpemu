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

        // V76.3.8.3: dual physical queues follow resource/guest synchronization,
        // not host lane alternation.  `resource` is the default whenever the
        // byte-range hazard tracker is enabled. `conservative` restores the
        // V74.0.113.1 whole-opposite-lane wait for A/B/recovery.
        private static readonly bool _resourceScopedDualQueueV76383 =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_DUAL_QUEUE_SYNC_POLICY"),
                "conservative",
                StringComparison.OrdinalIgnoreCase);
        private static long _v76383ResourceScopedSwitchBypassCount;
        private static long _v76383ResourceScopedHazardWaitCount;
        private static long _v76383ConservativeFallbackCount;
        private static long _v76383PresentBypassCount;

        private ulong ResolvePhysicalCrossQueueWaitV76383(
            bool computeLane,
            bool physicalLaneSwitch,
            bool hasTrackedAccess,
            ulong trackedWaitValue)
        {
            if (!physicalLaneSwitch)
            {
                return trackedWaitValue;
            }

            if (hasTrackedAccess)
            {
                if (trackedWaitValue != 0)
                {
                    Interlocked.Increment(ref _v76383ResourceScopedHazardWaitCount);
                }
                else if (_resourceScopedDualQueueV76383)
                {
                    Interlocked.Increment(ref _v76383ResourceScopedSwitchBypassCount);
                }
                return trackedWaitValue;
            }

            // If resource tracking was explicitly disabled, or recovery asked
            // for the old policy, preserve the proven conservative behavior.
            if (!_resourceAwareDualQueueV7615 || !_resourceScopedDualQueueV76383)
            {
                var fallback = computeLane
                    ? _graphicsQueueSignalValueV1131
                    : _computeQueueSignalValueV1131;
                Interlocked.Increment(ref _v76383ConservativeFallbackCount);
                return fallback;
            }

            Interlocked.Increment(ref _v76383ResourceScopedSwitchBypassCount);
            return 0;
        }

        private ulong ResolvePresentComputeWaitV76383(
            bool hasTrackedAccess,
            ulong trackedWaitValue)
        {
            if (hasTrackedAccess)
            {
                if (trackedWaitValue != 0)
                {
                    Interlocked.Increment(ref _v76383ResourceScopedHazardWaitCount);
                }
                return trackedWaitValue;
            }

            if (!_resourceAwareDualQueueV7615 || !_resourceScopedDualQueueV76383)
            {
                Interlocked.Increment(ref _v76383ConservativeFallbackCount);
                return _computeQueueSignalValueV1131;
            }

            Interlocked.Increment(ref _v76383PresentBypassCount);
            return 0;
        }

        private (bool HasTrackedAccess, ulong WaitValue) ResolveCrossQueueWaitV7615(
            bool computeLane,
            IReadOnlyList<TranslatedDrawResources> resources,
            IReadOnlyList<TranslatedDrawResources>? referencedResources,
            IReadOnlyList<VulkanQueueAccessV7615>? explicitAccessesV76383 = null)
        {
            if (!_resourceAwareDualQueueV7615)
            {
                return (false, 0);
            }

            BuildCrossQueueAccessesV7615(
                resources,
                referencedResources,
                null,
                false,
                explicitAccessesV76383);
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
            IReadOnlyList<TranslatedDrawResources>? referencedResources,
            IReadOnlyList<VulkanQueueAccessV7615>? explicitAccessesV76383 = null)
        {
            if (!_resourceAwareDualQueueV7615 || signalValue == 0)
            {
                return;
            }

            BuildCrossQueueAccessesV7615(
                resources,
                referencedResources,
                null,
                false,
                explicitAccessesV76383);
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
                    new VulkanQueueAccessV7615(
                        image.Address,
                        GetCrossQueueGuestImageExtentV762413(image),
                        false));
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
                    new VulkanQueueAccessV7615(
                        image.Address,
                        GetCrossQueueGuestImageExtentV762413(image),
                        false));
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
            bool extraWrite,
            IReadOnlyList<VulkanQueueAccessV7615>? explicitAccessesV76383 = null)
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
                    new VulkanQueueAccessV7615(
                        image.Address,
                        GetCrossQueueGuestImageExtentV762413(image),
                        extraWrite));
            }

            if (explicitAccessesV76383 is not null)
            {
                for (var index = 0; index < explicitAccessesV76383.Count; index++)
                {
                    var access = explicitAccessesV76383[index];
                    if (access.Address != 0)
                    {
                        _crossQueueAccessScratchV7615.Add(access);
                    }
                }
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
                        new VulkanQueueAccessV7615(
                            global.BaseAddress,
                            Math.Max(global.GuestSize, 1UL),
                            global.Writable));
                }
            }

            foreach (var texture in resource.Textures)
            {
                if (texture is not null && texture.Address != 0)
                {
                    _crossQueueAccessScratchV7615.Add(
                        new VulkanQueueAccessV7615(
                            texture.Address,
                            GetCrossQueueTextureExtentV762413(texture),
                            texture.IsStorage));
                }
            }

            foreach (var vertex in resource.VertexBuffers)
            {
                if (vertex.GuestAddress != 0)
                {
                    _crossQueueAccessScratchV7615.Add(
                        new VulkanQueueAccessV7615(
                            vertex.GuestAddress,
                            Math.Max(vertex.Size, 1UL),
                            false));
                }
            }

            foreach (var image in resource.QueueHazardImagesV7615)
            {
                if (image is not null && image.Address != 0)
                {
                    _crossQueueAccessScratchV7615.Add(
                        new VulkanQueueAccessV7615(
                            image.Address,
                            GetCrossQueueGuestImageExtentV762413(image),
                            true));
                }
            }
        }

        // V76.2.4.13: V76.0.26 upgraded the hazard tracker to byte ranges, but
        // image accesses still registered a one-byte interval.  That misses
        // cross-queue hazards whenever two guest texture descriptors alias the
        // same allocation at different base offsets.  Bink2 uses many compute
        // ping-pong/alias views, so track the actual guest image extent.
        private static ulong GetCrossQueueTextureExtentV762413(
            TextureResource texture)
        {
            if (texture.GuestImage is { } guestImage)
            {
                return GetCrossQueueGuestImageExtentV762413(guestImage);
            }

            return 1;
        }

        private static ulong GetCrossQueueGuestImageExtentV762413(
            GuestImageResource image)
        {
            var width = Math.Max(
                image.LogicalWidth != 0 ? image.LogicalWidth : image.Width,
                1u);
            var height = Math.Max(
                image.LogicalHeight != 0 ? image.LogicalHeight : image.Height,
                1u);
            var depth = Math.Max(
                image.LogicalDepth != 0 ? image.LogicalDepth : image.Depth,
                1u);
            var bytesPerPixel = Math.Max(GetReadbackBytesPerPixel(image.Format), 1u);

            var extent = (ulong)width * height;
            if (extent > ulong.MaxValue / depth)
            {
                return ulong.MaxValue;
            }
            extent *= depth;
            if (extent > ulong.MaxValue / bytesPerPixel)
            {
                return ulong.MaxValue;
            }
            return Math.Max(extent * bytesPerPixel, 1UL);
        }
    }
}
