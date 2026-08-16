// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using Silk.NET.Vulkan;
using VkBuffer = Silk.NET.Vulkan.Buffer;

namespace SharpEmu.Libs.VideoOut;

internal readonly record struct VulkanDeviceBufferPoolKey(
    BufferUsageFlags Usage,
    ulong Capacity);

internal readonly record struct VulkanDeviceBufferAllocation(
    VkBuffer Buffer,
    DeviceMemory Memory,
    VulkanDeviceBufferPoolKey Key);

/// <summary>
/// Fence-retired cache for DEVICE_LOCAL Vulkan buffers. Unlike
/// <see cref="VulkanHostBufferPool"/>, these allocations are never mapped and
/// consume the device-local heap on discrete GPUs.
/// </summary>
internal sealed class VulkanDeviceBufferPool : IDisposable
{
    private readonly object _gate = new();
    private readonly Dictionary<
        VulkanDeviceBufferPoolKey,
        Stack<VulkanDeviceBufferAllocation>> _available = [];
    private readonly Dictionary<ulong, VulkanDeviceBufferAllocation> _allocations = [];
    private readonly HashSet<ulong> _cachedHandles = [];
    private readonly Action<VulkanDeviceBufferAllocation> _destroy;

    public VulkanDeviceBufferPool(
        ulong maximumCachedBytes,
        Action<VulkanDeviceBufferAllocation> destroy)
    {
        MaximumCachedBytes = maximumCachedBytes;
        _destroy = destroy;
    }

    public ulong MaximumCachedBytes { get; }

    public ulong CachedBytes { get; private set; }

    public bool TryRent(
        VulkanDeviceBufferPoolKey key,
        out VulkanDeviceBufferAllocation allocation)
    {
        lock (_gate)
        {
            if (!_available.TryGetValue(key, out var available) ||
                !available.TryPop(out allocation))
            {
                allocation = default;
                return false;
            }

            _cachedHandles.Remove(allocation.Buffer.Handle);
            CachedBytes -= allocation.Key.Capacity;
            return true;
        }
    }

    public void Register(VulkanDeviceBufferAllocation allocation)
    {
        if (allocation.Buffer.Handle == 0)
        {
            throw new ArgumentException(
                "A pooled device buffer must have a valid handle.",
                nameof(allocation));
        }

        lock (_gate)
        {
            _allocations.Add(allocation.Buffer.Handle, allocation);
        }
    }

    public bool Return(VkBuffer buffer, DeviceMemory memory)
    {
        VulkanDeviceBufferAllocation? toDestroy = null;
        lock (_gate)
        {
            if (!_allocations.TryGetValue(buffer.Handle, out var allocation) ||
                allocation.Memory.Handle != memory.Handle)
            {
                return false;
            }

            if (!_cachedHandles.Add(buffer.Handle))
            {
                return true;
            }

            if (allocation.Key.Capacity > MaximumCachedBytes - CachedBytes)
            {
                _cachedHandles.Remove(buffer.Handle);
                _allocations.Remove(buffer.Handle);
                toDestroy = allocation;
            }
            else
            {
                if (!_available.TryGetValue(allocation.Key, out var available))
                {
                    available = [];
                    _available.Add(allocation.Key, available);
                }

                available.Push(allocation);
                CachedBytes += allocation.Key.Capacity;
            }
        }

        if (toDestroy is { } destroy)
        {
            _destroy(destroy);
        }

        return true;
    }

    public void Dispose()
    {
        List<VulkanDeviceBufferAllocation> toDestroy;
        lock (_gate)
        {
            toDestroy = new List<VulkanDeviceBufferAllocation>(_allocations.Values);
            _allocations.Clear();
            _available.Clear();
            _cachedHandles.Clear();
            CachedBytes = 0;
        }

        foreach (var allocation in toDestroy)
        {
            _destroy(allocation);
        }
    }
}
