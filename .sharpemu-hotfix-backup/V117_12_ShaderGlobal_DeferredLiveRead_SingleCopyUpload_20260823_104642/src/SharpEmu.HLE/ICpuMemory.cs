// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers;

namespace SharpEmu.HLE;

public interface ICpuMemory
{
    bool TryRead(ulong virtualAddress, Span<byte> destination);

    bool TryWrite(ulong virtualAddress, ReadOnlySpan<byte> source);

    bool TryCompare(ulong virtualAddress, ReadOnlySpan<byte> expected) => false;

    bool TryCopy(ulong destinationAddress, ulong sourceAddress, ulong length) => false;

    /// <summary>
    /// Repeats <paramref name="pattern"/> directly into guest memory without
    /// requiring callers to allocate a buffer as large as the destination.
    /// Implementations backed by contiguous guest memory should override this
    /// method; the bounded fallback keeps compatibility with other memories.
    /// </summary>
    bool TryFillPattern(ulong virtualAddress, ReadOnlySpan<byte> pattern, ulong length)
    {
        if (length == 0)
        {
            return true;
        }
        if (pattern.IsEmpty)
        {
            return false;
        }
        if (this is ICpuMemoryWrapper wrapper && !ReferenceEquals(wrapper.Inner, this))
        {
            return wrapper.Inner.TryFillPattern(virtualAddress, pattern, length);
        }

        const int maximumChunkBytes = 1024 * 1024;
        int chunkLength;
        if (length <= (ulong)maximumChunkBytes)
        {
            chunkLength = checked((int)length);
        }
        else if (pattern.Length >= maximumChunkBytes)
        {
            chunkLength = pattern.Length;
        }
        else
        {
            chunkLength = maximumChunkBytes - (maximumChunkBytes % pattern.Length);
        }

        var rented = ArrayPool<byte>.Shared.Rent(chunkLength);
        try
        {
            var chunk = rented.AsSpan(0, chunkLength);
            var seeded = Math.Min(pattern.Length, chunk.Length);
            pattern[..seeded].CopyTo(chunk);
            while (seeded < chunk.Length)
            {
                var copyLength = Math.Min(seeded, chunk.Length - seeded);
                chunk[..copyLength].CopyTo(chunk.Slice(seeded, copyLength));
                seeded += copyLength;
            }

            ulong offset = 0;
            while (offset < length)
            {
                var writeLength = checked((int)Math.Min((ulong)chunkLength, length - offset));
                if (!TryWrite(virtualAddress + offset, chunk[..writeLength]))
                {
                    return false;
                }

                offset += (ulong)writeLength;
            }

            return true;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(rented);
        }
    }
}
