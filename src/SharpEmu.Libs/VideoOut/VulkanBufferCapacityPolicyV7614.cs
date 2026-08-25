// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Numerics;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// V76.0.14 transient-buffer size classes. Small buffers keep the existing
/// power-of-two behavior; large uploads/detile buffers use fixed alignments so
/// a 65 MiB request no longer reserves a 128 MiB allocation just to participate
/// in a pool.
/// </summary>
internal static class VulkanBufferCapacityPolicyV7614
{
    private const ulong Minimum = 4UL * 1024UL;
    private const ulong SmallLimit = 4UL * 1024UL * 1024UL;
    private const ulong MediumLimit = 64UL * 1024UL * 1024UL;
    private const ulong LargeLimit = 256UL * 1024UL * 1024UL;
    private const ulong MediumAlignment = 1UL * 1024UL * 1024UL;
    private const ulong LargeAlignment = 4UL * 1024UL * 1024UL;
    private const ulong HugeAlignment = 16UL * 1024UL * 1024UL;

    internal static ulong Round(ulong requested)
    {
        var size = Math.Max(requested, Minimum);
        if (size <= SmallLimit)
        {
            return BitOperations.RoundUpToPowerOf2(size);
        }

        var alignment = size <= MediumLimit
            ? MediumAlignment
            : size <= LargeLimit
                ? LargeAlignment
                : HugeAlignment;
        return checked((size + alignment - 1) / alignment * alignment);
    }
}
