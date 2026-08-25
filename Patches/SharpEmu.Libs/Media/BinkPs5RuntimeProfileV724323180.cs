// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Buffers.Binary;
using System.IO;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.31.8: non-proprietary Bink container profile used by the PS5
/// compatibility bridge.  It only inspects public container metadata; decode,
/// YUV conversion, HDR/gamma and audio remain owned by the installed RAD tool.
/// This deliberately avoids the old NIHAV -> BGRA copy/convert hot path when
/// RAD mode is active.
/// </summary>
internal static class BinkPs5RuntimeProfileV724323180
{
    internal readonly record struct MovieProfile(
        string Tag,
        uint Width,
        uint Height,
        uint Frames,
        uint FramesPerSecondNumerator,
        uint FramesPerSecondDenominator)
    {
        internal double FramesPerSecond =>
            FramesPerSecondDenominator == 0
                ? 0
                : (double)FramesPerSecondNumerator / FramesPerSecondDenominator;
    }

    internal static bool TryInspect(
        string moviePath,
        out MovieProfile profile)
    {
        profile = default;
        if (string.IsNullOrWhiteSpace(moviePath) || !File.Exists(moviePath))
        {
            return false;
        }

        Span<byte> header = stackalloc byte[48];
        try
        {
            using var stream = new FileStream(
                moviePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite);
            stream.ReadExactly(header);

            var tag = Encoding.ASCII.GetString(header[..4]);
            if (!tag.StartsWith("KB2", StringComparison.Ordinal) &&
                !tag.StartsWith("BIK", StringComparison.Ordinal))
            {
                return false;
            }

            var frames = BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(8, 4));
            var width = BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x14, 4));
            var height = BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x18, 4));
            var fpsNumerator = BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x1C, 4));
            var fpsDenominator = BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x20, 4));

            if (width == 0 || height == 0 || width > 16384 || height > 16384 ||
                fpsNumerator == 0 || fpsDenominator == 0)
            {
                return false;
            }

            profile = new MovieProfile(
                tag,
                width,
                height,
                frames,
                fpsNumerator,
                fpsDenominator);
            return true;
        }
        catch (Exception ex) when (
            ex is IOException or
            UnauthorizedAccessException or
            EndOfStreamException)
        {
            return false;
        }
    }

    internal static void Log(string moviePath, MovieProfile profile)
    {
        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.ps5_runtime_profile " +
            $"file='{Path.GetFileName(moviePath)}' tag='{profile.Tag}' " +
            $"size={profile.Width}x{profile.Height} frames={profile.Frames} " +
            $"fps={profile.FramesPerSecondNumerator}/{profile.FramesPerSecondDenominator} " +
            "decode_owner=official-rad color_owner=official-rad " +
            "copy_path=rad-child-hwnd sharpemu_bgra_conversion=False");
    }
}
