// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Stable Bink2 visual/audio defaults for the host movie bridge.
///
/// The current Demon’s Souls boot path is known to use full-range BT.709.
/// The raw NIHAV PGMYUV chroma order also needs the U/V selection used by the
/// validated fallback path.  The FFmpeg/swscale path has a separate swap
/// because it consumes the contiguous planar buffer directly.
/// </summary>
internal static class BinkVisualAudioRuntimeDefaultsV7241
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_V7241_DEFAULTS"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }

        // EOF/frame-count, not nominal wall clock, owns completion.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_REALTIME_DEADLINE",
            "0");

        // Prefer swscale when available, and fix its physical I420 U/V input.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_FFMPEG_COLOR",
            "1");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_FFMPEG_UV_SWAP",
            "1");

        // The LUT/fallback path must use the same logical chroma ordering.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_NIHAV_UV_SWAP",
            "1");

        // Demon’s Souls Bink content has already selected full range in the
        // decoder’s auto probe.  Make that deterministic and avoid per-movie
        // range misclassification.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_NIHAV_AUTO_RANGE",
            "0");

        // Host audio bridge.  Set SHARPEMU_BINK_HOST_AUDIO=0 to disable.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_HOST_AUDIO",
            "1");
    }
}
