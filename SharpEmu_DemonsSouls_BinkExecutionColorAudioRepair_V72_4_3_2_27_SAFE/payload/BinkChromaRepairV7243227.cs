// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.27: conservative Bink2 chroma-boundary repair.
///
/// The direct NIHAV RAW-frame audit proved that Demon's Souls luma is clean
/// while rectangular discontinuities are already present in the decoded U/V
/// planes before SharpEmu performs color conversion or presentation.
///
/// Repair only chroma block boundaries. Luma is never modified.
/// </summary>
internal static class BinkChromaRepairV7243227
{
    private const int ChromaBlock = 8;
    private const int DefaultThreshold = 24;

    public static void RepairInPlace(
        Span<byte> uPlane,
        Span<byte> vPlane,
        int width,
        int height,
        string moviePath)
    {
        if (!IsEnabled(moviePath) ||
            width < ChromaBlock * 2 ||
            height < ChromaBlock * 2)
        {
            return;
        }

        var required = checked(width * height);
        if (uPlane.Length < required || vPlane.Length < required)
        {
            return;
        }

        var threshold = ResolveThreshold();
        RepairPlane(uPlane[..required], width, height, threshold);
        RepairPlane(vPlane[..required], width, height, threshold);
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

        if (string.IsNullOrWhiteSpace(moviePath))
        {
            return false;
        }

        // Keep the compatibility repair scoped to the Demon's Souls content
        // used by the accumulated audit instead of changing unrelated titles.
        if (moviePath.Contains(
                "PPSA01341",
                StringComparison.OrdinalIgnoreCase) ||
            moviePath.Contains(
                "PPSA25646",
                StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return false;
    }

    private static int ResolveThreshold()
    {
        var configured =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD");

        if (int.TryParse(configured, out var parsed))
        {
            return Math.Clamp(parsed, 4, 48);
        }

        return DefaultThreshold;
    }

    private static void RepairPlane(
        Span<byte> plane,
        int width,
        int height,
        int threshold)
    {
        // Require a small local-gradient envelope in addition to the cross-
        // boundary difference. This avoids blurring real picture edges.
        var localThreshold = Math.Max(6, (threshold * 5 + 4) / 8);

        // Vertical 8x8 chroma block boundaries.
        for (var y = 0; y < height; y++)
        {
            var row = y * width;

            for (var x = ChromaBlock;
                 x < width;
                 x += ChromaBlock)
            {
                var p1Index = row + x - 2;
                var p0Index = row + x - 1;
                var q0Index = row + x;
                var q1Index = row + x + 1;

                if (q1Index >= row + width)
                {
                    break;
                }

                SmoothBoundary(
                    plane,
                    p1Index,
                    p0Index,
                    q0Index,
                    q1Index,
                    threshold,
                    localThreshold);
            }
        }

        // Horizontal 8x8 chroma block boundaries.
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

        // Symmetric four-sample boundary blend. Only the two samples adjacent
        // to the block boundary are changed; p1/q1 stay intact.
        var newP0 = (p1 + (p0 * 2) + q0 + 2) >> 2;
        var newQ0 = (p0 + (q0 * 2) + q1 + 2) >> 2;

        plane[p0Index] = (byte)Math.Clamp(newP0, 0, 255);
        plane[q0Index] = (byte)Math.Clamp(newQ0, 0, 255);
    }
}
