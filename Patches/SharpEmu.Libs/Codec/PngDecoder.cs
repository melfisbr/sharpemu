// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;
using System.IO.Compression;

namespace SharpEmu.Libs.Codec;

/// <summary>
/// Small dependency-free PNG decoder shared by libScePngDec compatibility code.
/// Supports the 8-bit non-interlaced PNG formats used by game UI assets:
/// grayscale, RGB, indexed color, grayscale+alpha and RGBA.
/// </summary>
internal static class PngDecoder
{
    internal const ushort ColorSpaceGrayscale = 2;
    internal const ushort ColorSpaceRgb = 3;
    internal const ushort ColorSpaceClut = 4;
    internal const ushort ColorSpaceGrayscaleAlpha = 18;
    internal const ushort ColorSpaceRgba = 19;
    internal const uint ImageFlagAdam7 = 1;
    internal const uint ImageFlagTransparency = 2;

    private const uint CrcPolynomial = 0xEDB88320;
    private const uint MaxDimension = 16384;
    private static readonly uint[] CrcTable = BuildCrcTable();

    private static ReadOnlySpan<byte> Signature =>
    [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ];

    internal readonly record struct HeaderInfo(
        uint Width,
        uint Height,
        ushort ColorSpace,
        ushort BitDepth,
        uint ImageFlags,
        byte ColorType)
    {
        public bool HasSourceAlpha =>
            ColorSpace is ColorSpaceRgba or ColorSpaceGrayscaleAlpha ||
            (ImageFlags & ImageFlagTransparency) != 0;
    }

    internal static bool TryReadHeader(ReadOnlySpan<byte> png, out HeaderInfo info)
    {
        info = default;
        if (png.Length < 33 || !png[..8].SequenceEqual(Signature))
        {
            return false;
        }

        var chunkLength = BinaryPrimitives.ReadUInt32BigEndian(png.Slice(8, 4));
        if (chunkLength != 13 || !png.Slice(12, 4).SequenceEqual("IHDR"u8))
        {
            return false;
        }

        var ihdr = png.Slice(16, 13);
        if (!ValidateChunkCrc(png.Slice(12, 4), ihdr, png.Slice(29, 4)))
        {
            return false;
        }

        var width = BinaryPrimitives.ReadUInt32BigEndian(ihdr[..4]);
        var height = BinaryPrimitives.ReadUInt32BigEndian(ihdr.Slice(4, 4));
        var bitDepth = ihdr[8];
        var colorType = ihdr[9];
        var compression = ihdr[10];
        var filter = ihdr[11];
        var interlace = ihdr[12];
        var colorSpace = colorType switch
        {
            0 => ColorSpaceGrayscale,
            2 => ColorSpaceRgb,
            3 => ColorSpaceClut,
            4 => ColorSpaceGrayscaleAlpha,
            6 => ColorSpaceRgba,
            _ => (ushort)0,
        };

        if (width == 0 || height == 0 || width > MaxDimension || height > MaxDimension ||
            compression != 0 || filter != 0 || interlace > 1 || colorSpace == 0)
        {
            return false;
        }

        var flags = interlace == 1 ? ImageFlagAdam7 : 0u;
        var offset = 33;
        while (offset <= png.Length - 12)
        {
            var length = BinaryPrimitives.ReadUInt32BigEndian(png.Slice(offset, 4));
            if (length > int.MaxValue || offset > png.Length - 12 - (int)length)
            {
                return false;
            }

            var type = png.Slice(offset + 4, 4);
            var data = png.Slice(offset + 8, (int)length);
            var crc = png.Slice(offset + 8 + (int)length, 4);
            if (!ValidateChunkCrc(type, data, crc))
            {
                return false;
            }

            if (type.SequenceEqual("tRNS"u8))
            {
                flags |= ImageFlagTransparency;
            }

            if (type.SequenceEqual("IDAT"u8) || type.SequenceEqual("IEND"u8))
            {
                break;
            }

            offset += checked((int)length + 12);
        }

        info = new HeaderInfo(width, height, colorSpace, bitDepth, flags, colorType);
        return true;
    }

    internal static bool TryDecodeRgba(
        ReadOnlySpan<byte> png,
        out byte[] rgba,
        out HeaderInfo info)
    {
        rgba = [];
        info = default;
        try
        {
            if (!TryReadHeader(png, out info) || info.BitDepth != 8 ||
                (info.ImageFlags & ImageFlagAdam7) != 0)
            {
                return false;
            }

            using var compressed = new MemoryStream();
            byte[] palette = [];
            byte[] transparency = [];
            var offset = 8;
            var sawIend = false;
            while (offset <= png.Length - 12)
            {
                var length = BinaryPrimitives.ReadUInt32BigEndian(png.Slice(offset, 4));
                if (length > int.MaxValue || offset > png.Length - 12 - (int)length)
                {
                    return false;
                }

                var type = png.Slice(offset + 4, 4);
                var data = png.Slice(offset + 8, (int)length);
                var crc = png.Slice(offset + 8 + (int)length, 4);
                if (!ValidateChunkCrc(type, data, crc))
                {
                    return false;
                }

                if (type.SequenceEqual("PLTE"u8))
                {
                    if (data.Length == 0 || data.Length > 256 * 3 || data.Length % 3 != 0)
                    {
                        return false;
                    }
                    palette = data.ToArray();
                }
                else if (type.SequenceEqual("tRNS"u8))
                {
                    transparency = data.ToArray();
                }
                else if (type.SequenceEqual("IDAT"u8))
                {
                    compressed.Write(data);
                }
                else if (type.SequenceEqual("IEND"u8))
                {
                    sawIend = true;
                    break;
                }

                offset += checked((int)length + 12);
            }

            if (!sawIend || compressed.Length == 0 || (info.ColorType == 3 && palette.Length == 0))
            {
                return false;
            }

            var sourceBytesPerPixel = info.ColorType switch
            {
                0 => 1,
                2 => 3,
                3 => 1,
                4 => 2,
                6 => 4,
                _ => 0,
            };
            if (sourceBytesPerPixel == 0)
            {
                return false;
            }

            var stride = checked((int)info.Width * sourceBytesPerPixel);
            var scanlineLength = checked(stride + 1);
            var decompressedLength = checked(scanlineLength * (int)info.Height);
            var scanlines = GC.AllocateUninitializedArray<byte>(decompressedLength);
            compressed.Position = 0;
            using (var zlib = new ZLibStream(compressed, CompressionMode.Decompress, leaveOpen: true))
            {
                zlib.ReadExactly(scanlines);
                if (zlib.ReadByte() != -1)
                {
                    return false;
                }
            }

            var reconstructed = GC.AllocateUninitializedArray<byte>(checked(stride * (int)info.Height));
            for (var y = 0; y < (int)info.Height; y++)
            {
                var sourceLine = scanlines.AsSpan(y * scanlineLength + 1, stride);
                var targetLine = reconstructed.AsSpan(y * stride, stride);
                var previousLine = y == 0
                    ? ReadOnlySpan<byte>.Empty
                    : reconstructed.AsSpan((y - 1) * stride, stride);
                if (!TryUnfilter(
                        scanlines[y * scanlineLength],
                        sourceLine,
                        previousLine,
                        targetLine,
                        sourceBytesPerPixel))
                {
                    return false;
                }
            }

            rgba = GC.AllocateUninitializedArray<byte>(checked((int)info.Width * (int)info.Height * 4));
            for (int sourceOffset = 0, targetOffset = 0;
                 sourceOffset < reconstructed.Length;
                 sourceOffset += sourceBytesPerPixel, targetOffset += 4)
            {
                switch (info.ColorType)
                {
                    case 0:
                    {
                        var gray = reconstructed[sourceOffset];
                        var alpha = (byte)0xFF;
                        if (transparency.Length >= 2 &&
                            BinaryPrimitives.ReadUInt16BigEndian(transparency) == gray)
                        {
                            alpha = 0;
                        }
                        rgba[targetOffset] = gray;
                        rgba[targetOffset + 1] = gray;
                        rgba[targetOffset + 2] = gray;
                        rgba[targetOffset + 3] = alpha;
                        break;
                    }
                    case 2:
                    {
                        var r = reconstructed[sourceOffset];
                        var g = reconstructed[sourceOffset + 1];
                        var b = reconstructed[sourceOffset + 2];
                        var alpha = (byte)0xFF;
                        if (transparency.Length >= 6 &&
                            BinaryPrimitives.ReadUInt16BigEndian(transparency.AsSpan(0, 2)) == r &&
                            BinaryPrimitives.ReadUInt16BigEndian(transparency.AsSpan(2, 2)) == g &&
                            BinaryPrimitives.ReadUInt16BigEndian(transparency.AsSpan(4, 2)) == b)
                        {
                            alpha = 0;
                        }
                        rgba[targetOffset] = r;
                        rgba[targetOffset + 1] = g;
                        rgba[targetOffset + 2] = b;
                        rgba[targetOffset + 3] = alpha;
                        break;
                    }
                    case 3:
                    {
                        var index = reconstructed[sourceOffset];
                        var paletteOffset = index * 3;
                        if (paletteOffset > palette.Length - 3)
                        {
                            rgba = [];
                            return false;
                        }
                        rgba[targetOffset] = palette[paletteOffset];
                        rgba[targetOffset + 1] = palette[paletteOffset + 1];
                        rgba[targetOffset + 2] = palette[paletteOffset + 2];
                        rgba[targetOffset + 3] = index < transparency.Length ? transparency[index] : (byte)0xFF;
                        break;
                    }
                    case 4:
                    {
                        var gray = reconstructed[sourceOffset];
                        rgba[targetOffset] = gray;
                        rgba[targetOffset + 1] = gray;
                        rgba[targetOffset + 2] = gray;
                        rgba[targetOffset + 3] = reconstructed[sourceOffset + 1];
                        break;
                    }
                    case 6:
                        reconstructed.AsSpan(sourceOffset, 4).CopyTo(rgba.AsSpan(targetOffset, 4));
                        break;
                    default:
                        rgba = [];
                        return false;
                }
            }

            return true;
        }
        catch (Exception ex) when (ex is InvalidDataException or EndOfStreamException or OverflowException or IOException)
        {
            rgba = [];
            info = default;
            return false;
        }
    }

    private static bool ValidateChunkCrc(
        ReadOnlySpan<byte> chunkType,
        ReadOnlySpan<byte> chunkData,
        ReadOnlySpan<byte> crcBytes)
    {
        if (crcBytes.Length < 4)
        {
            return false;
        }
        var expected = BinaryPrimitives.ReadUInt32BigEndian(crcBytes[..4]);
        var crc = UpdateCrc(uint.MaxValue, chunkType);
        return ~UpdateCrc(crc, chunkData) == expected;
    }

    private static uint UpdateCrc(uint crc, ReadOnlySpan<byte> bytes)
    {
        foreach (var value in bytes)
        {
            crc = CrcTable[(byte)(crc ^ value)] ^ (crc >> 8);
        }
        return crc;
    }

    private static uint[] BuildCrcTable()
    {
        var table = new uint[256];
        for (var index = 0; index < table.Length; index++)
        {
            var value = (uint)index;
            for (var bit = 0; bit < 8; bit++)
            {
                value = (value & 1) != 0 ? CrcPolynomial ^ (value >> 1) : value >> 1;
            }
            table[index] = value;
        }
        return table;
    }

    private static bool TryUnfilter(
        byte filter,
        ReadOnlySpan<byte> source,
        ReadOnlySpan<byte> previous,
        Span<byte> target,
        int bytesPerPixel)
    {
        if (filter > 4)
        {
            return false;
        }

        for (var x = 0; x < source.Length; x++)
        {
            var left = x >= bytesPerPixel ? target[x - bytesPerPixel] : (byte)0;
            var above = previous.IsEmpty ? (byte)0 : previous[x];
            var upperLeft = !previous.IsEmpty && x >= bytesPerPixel ? previous[x - bytesPerPixel] : (byte)0;
            target[x] = filter switch
            {
                0 => source[x],
                1 => unchecked((byte)(source[x] + left)),
                2 => unchecked((byte)(source[x] + above)),
                3 => unchecked((byte)(source[x] + ((left + above) >> 1))),
                4 => unchecked((byte)(source[x] + Paeth(left, above, upperLeft))),
                _ => source[x],
            };
        }
        return true;
    }

    private static byte Paeth(byte left, byte above, byte upperLeft)
    {
        var estimate = left + above - upperLeft;
        var leftDistance = Math.Abs(estimate - left);
        var aboveDistance = Math.Abs(estimate - above);
        var upperLeftDistance = Math.Abs(estimate - upperLeft);
        return leftDistance <= aboveDistance && leftDistance <= upperLeftDistance
            ? left
            : aboveDistance <= upperLeftDistance ? above : upperLeft;
    }
}
