// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.28: block-wide chroma-bias repair for audited Demon's Souls KB2j.
/// V27 only blended immediate 8x8 borders. V28 detects isolated U/V block-mean
/// outliers, shifts the whole block toward a robust neighbour median, then
/// keeps the conservative boundary blend. Luma is never modified.
/// </summary>
internal static class BinkChromaRepairV7243227
{
    private const int ChromaBlock = 8;
    private const int DefaultBoundaryThreshold = 24;
    private const int DefaultBiasThreshold = 4;
    private const int DefaultNeighbourSpread = 12;
    private const int DefaultBiasStrengthPercent = 75;

    public static void RepairInPlace(
        Span<byte> uPlane,
        Span<byte> vPlane,
        int width,
        int height,
        string moviePath)
    {
        if (!IsEnabled(moviePath) ||
            width < ChromaBlock * 3 ||
            height < ChromaBlock * 3)
        {
            return;
        }

        var required = checked(width * height);
        if (uPlane.Length < required || vPlane.Length < required)
        {
            return;
        }

        var boundaryThreshold = Resolve(
            "SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD",
            DefaultBoundaryThreshold,
            4,
            48);
        var biasThreshold = Resolve(
            "SHARPEMU_BINK_CHROMA_BLOCK_BIAS_THRESHOLD",
            DefaultBiasThreshold,
            2,
            24);
        var neighbourSpread = Resolve(
            "SHARPEMU_BINK_CHROMA_BLOCK_NEIGHBOUR_SPREAD",
            DefaultNeighbourSpread,
            4,
            32);
        var strength = Resolve(
            "SHARPEMU_BINK_CHROMA_BLOCK_BIAS_STRENGTH",
            DefaultBiasStrengthPercent,
            25,
            100);

        RepairPlane(
            uPlane[..required],
            width,
            height,
            boundaryThreshold,
            biasThreshold,
            neighbourSpread,
            strength);
        RepairPlane(
            vPlane[..required],
            width,
            height,
            boundaryThreshold,
            biasThreshold,
            neighbourSpread,
            strength);
    }

    private static int Resolve(
        string name,
        int fallback,
        int min,
        int max)
    {
        var configured =
            Environment.GetEnvironmentVariable(name);

        return int.TryParse(configured, out var parsed)
            ? Math.Clamp(parsed, min, max)
            : fallback;
    }

    private static bool IsEnabled(string moviePath)
    {
        var configured =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_CHROMA_DEBLOCK");

        if (string.Equals(configured, "0", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "false", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_CHROMA_DEBLOCK_ALL"),
                "1",
                StringComparison.Ordinal))
        {
            return true;
        }

        return !string.IsNullOrWhiteSpace(moviePath) &&
               (moviePath.Contains(
                    "PPSA01341",
                    StringComparison.OrdinalIgnoreCase) ||
                moviePath.Contains(
                    "PPSA25646",
                    StringComparison.OrdinalIgnoreCase));
    }

    private static void RepairPlane(
        Span<byte> plane,
        int width,
        int height,
        int boundaryThreshold,
        int biasThreshold,
        int neighbourSpread,
        int strength)
    {
        RepairBlockBias(
            plane,
            width,
            height,
            biasThreshold,
            neighbourSpread,
            strength);
        RepairBoundaries(
            plane,
            width,
            height,
            boundaryThreshold);
    }

    private static void RepairBlockBias(
        Span<byte> plane,
        int width,
        int height,
        int biasThreshold,
        int neighbourSpread,
        int strength)
    {
        var blocksX = width / ChromaBlock;
        var blocksY = height / ChromaBlock;
        var count = checked(blocksX * blocksY);

        var means =
            GC.AllocateUninitializedArray<byte>(count);
        var offsets =
            GC.AllocateUninitializedArray<sbyte>(count);
        Array.Clear(offsets);

        for (var by = 0; by < blocksY; by++)
        {
            var py = by * ChromaBlock;

            for (var bx = 0; bx < blocksX; bx++)
            {
                var px = bx * ChromaBlock;
                var sum = 0;

                for (var y = 0; y < ChromaBlock; y++)
                {
                    var row = (py + y) * width + px;

                    for (var x = 0; x < ChromaBlock; x++)
                    {
                        sum += plane[row + x];
                    }
                }

                means[by * blocksX + bx] =
                    (byte)((sum + 32) >> 6);
            }
        }

        Span<int> neighbours = stackalloc int[8];

        for (var by = 1; by < blocksY - 1; by++)
        {
            for (var bx = 1; bx < blocksX - 1; bx++)
            {
                var n = 0;

                for (var dy = -1; dy <= 1; dy++)
                {
                    for (var dx = -1; dx <= 1; dx++)
                    {
                        if (dx == 0 && dy == 0)
                        {
                            continue;
                        }

                        neighbours[n++] =
                            means[
                                (by + dy) * blocksX +
                                (bx + dx)];
                    }
                }

                SortEight(neighbours);

                var median =
                    (neighbours[3] + neighbours[4] + 1) >> 1;
                var spread =
                    neighbours[6] - neighbours[1];
                var index = by * blocksX + bx;
                var delta =
                    median - (int)means[index];

                if (spread > neighbourSpread ||
                    Math.Abs(delta) < biasThreshold)
                {
                    continue;
                }

                var correction =
                    (delta * strength +
                     (delta >= 0 ? 50 : -50)) /
                    100;

                offsets[index] =
                    (sbyte)Math.Clamp(correction, -32, 32);
            }
        }

        for (var by = 1; by < blocksY - 1; by++)
        {
            var py = by * ChromaBlock;

            for (var bx = 1; bx < blocksX - 1; bx++)
            {
                var correction =
                    (int)offsets[by * blocksX + bx];

                if (correction == 0)
                {
                    continue;
                }

                var px = bx * ChromaBlock;

                for (var y = 0; y < ChromaBlock; y++)
                {
                    var row = (py + y) * width + px;

                    for (var x = 0; x < ChromaBlock; x++)
                    {
                        plane[row + x] =
                            (byte)Math.Clamp(
                                (int)plane[row + x] + correction,
                                0,
                                255);
                    }
                }
            }
        }
    }

    private static void SortEight(Span<int> values)
    {
        for (var i = 1; i < 8; i++)
        {
            var value = values[i];
            var j = i - 1;

            while (j >= 0 && values[j] > value)
            {
                values[j + 1] = values[j];
                j--;
            }

            values[j + 1] = value;
        }
    }

    private static void RepairBoundaries(
        Span<byte> plane,
        int width,
        int height,
        int threshold)
    {
        var localThreshold =
            Math.Max(6, (threshold * 5 + 4) / 8);

        for (var y = 0; y < height; y++)
        {
            var row = y * width;

            for (var x = ChromaBlock;
                 x < width;
                 x += ChromaBlock)
            {
                var p1 = row + x - 2;
                var p0 = row + x - 1;
                var q0 = row + x;
                var q1 = row + x + 1;

                if (q1 >= row + width)
                {
                    break;
                }

                SmoothBoundary(
                    plane,
                    p1,
                    p0,
                    q0,
                    q1,
                    threshold,
                    localThreshold);
            }
        }

        for (var y = ChromaBlock;
             y < height;
             y += ChromaBlock)
        {
            if (y + 1 >= height)
            {
                break;
            }

            var p1Row = (y - 2) * width;
            var p0Row = (y - 1) * width;
            var q0Row = y * width;
            var q1Row = (y + 1) * width;

            for (var x = 0; x < width; x++)
            {
                SmoothBoundary(
                    plane,
                    p1Row + x,
                    p0Row + x,
                    q0Row + x,
                    q1Row + x,
                    threshold,
                    localThreshold);
            }
        }
    }

    private static void SmoothBoundary(
        Span<byte> plane,
        int p1Index,
        int p0Index,
        int q0Index,
        int q1Index,
        int threshold,
        int localThreshold)
    {
        var p1 = (int)plane[p1Index];
        var p0 = (int)plane[p0Index];
        var q0 = (int)plane[q0Index];
        var q1 = (int)plane[q1Index];

        if (Math.Abs(p0 - q0) > threshold ||
            Math.Abs(p1 - p0) > localThreshold ||
            Math.Abs(q1 - q0) > localThreshold)
        {
            return;
        }

        plane[p0Index] =
            (byte)Math.Clamp(
                (p1 + (p0 * 2) + q0 + 2) >> 2,
                0,
                255);
        plane[q0Index] =
            (byte)Math.Clamp(
                (p0 + (q0 * 2) + q1 + 2) >> 2,
                0,
                255);
    }
}
