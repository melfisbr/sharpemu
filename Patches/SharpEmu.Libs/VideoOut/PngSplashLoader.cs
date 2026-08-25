// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;
using System.IO.Compression;
using SharpEmu.Libs.Codec;

namespace SharpEmu.Libs.VideoOut;

internal static class PngSplashLoader
{
    private const uint CrcPolynomial = 0xEDB88320;
    private static readonly uint[] CrcTable = BuildCrcTable();

    private static ReadOnlySpan<byte> PngSignature =>
    [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ];

    public static bool TryLoad(out byte[] pixels, out uint width, out uint height)
        => TryLoad("pic0.png", requestRgba: false, out pixels, out width, out height);

    public static bool TryLoadIcon(out byte[] pixels, out uint width, out uint height)
        => TryLoad("icon0.png", requestRgba: true, out pixels, out width, out height);

    private static bool TryLoad(
        string fileName,
        bool requestRgba,
        out byte[] pixels,
        out uint width,
        out uint height)
    {
        pixels = [];
        width = 0;
        height = 0;

        try
        {
            var app0Root = Environment.GetEnvironmentVariable("SHARPEMU_APP0_DIR");
            if (string.IsNullOrWhiteSpace(app0Root))
            {
                return false;
            }

            var path = Path.Combine(app0Root, "sce_sys", fileName);
            if (!File.Exists(path))
            {
                return false;
            }

            return TryDecode(
                File.ReadAllBytes(path),
                out pixels,
                out width,
                out height,
                requestRgba);
        }
        catch
        {
            pixels = [];
            width = 0;
            height = 0;
            return false;
        }
    }

    private static bool TryDecode(
        ReadOnlySpan<byte> png,
        out byte[] pixels,
        out uint width,
        out uint height,
        bool requestRgba)
    {
        pixels = [];
        width = 0;
        height = 0;
        if (!PngDecoder.TryDecodeRgba(png, out var rgba, out var info))
        {
            return false;
        }

        width = info.Width;
        height = info.Height;
        pixels = rgba;
        if (!requestRgba)
        {
            for (var offset = 0; offset < pixels.Length; offset += 4)
            {
                var red = pixels[offset];
                pixels[offset] = pixels[offset + 2];
                pixels[offset + 2] = red;
            }
        }

        return true;
    }

    private static uint CalculateCrc(ReadOnlySpan<byte> chunkType, ReadOnlySpan<byte> chunkData)
    {
        var crc = UpdateCrc(uint.MaxValue, chunkType);
        return ~UpdateCrc(crc, chunkData);
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
                value = (value & 1) != 0
                    ? CrcPolynomial ^ (value >> 1)
                    : value >> 1;
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
        for (var x = 0; x < source.Length; x++)
        {
            var left = x >= bytesPerPixel ? target[x - bytesPerPixel] : (byte)0;
            var above = previous.IsEmpty ? (byte)0 : previous[x];
            var upperLeft = !previous.IsEmpty && x >= bytesPerPixel
                ? previous[x - bytesPerPixel]
                : (byte)0;
            target[x] = filter switch
            {
                0 => source[x],
                1 => unchecked((byte)(source[x] + left)),
                2 => unchecked((byte)(source[x] + above)),
                3 => unchecked((byte)(source[x] + ((left + above) >> 1))),
                4 => unchecked((byte)(source[x] + Paeth(left, above, upperLeft))),
                _ => source[x],
            };

            if (filter > 4)
            {
                return false;
            }
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
            : aboveDistance <= upperLeftDistance
                ? above
                : upperLeft;
    }
}
