// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2 real-time Bink policy.
///
/// V72.4.2 proved the audio extraction/playback path works, but forcing the
/// decode path to preserve every output frame made video fall behind audio.
/// Use NIHAV's inter-frame aware skip policy and a 960x540 cap while keeping
/// the corrected managed BT.709 conversion as the primary color path.
/// </summary>
internal static class BinkVisualAudioRuntimeDefaultsV7241
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_V7243_DEFAULTS"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }

        // Completion is still EOF/frame-count based. Do not reintroduce the
        // old hard wall-clock termination regression.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_REALTIME_DEADLINE",
            "0");

        // FFmpeg color never became ready in the failing lineage and imposed
        // a multi-second timeout. Keep the managed conversion primary.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_FFMPEG_COLOR",
            "0");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_FFMPEG_UV_SWAP",
            "0");

        // V72.4.3.2 consumes the repacked I420 planes explicitly as Y/U/V.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_NIHAV_UV_SWAP",
            "0");

        // The Demon’s Souls Bink samples consistently resolve to full range.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_NIHAV_AUTO_RANGE",
            "0");

        // 640x360 in V72.4.2 was visibly too conservative. 960x540 preserves
        // materially more image detail while remaining much cheaper than 1080p.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_OUTPUT_MAX_WIDTH",
            "960");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_OUTPUT_MAX_HEIGHT",
            "540");

        // Do not use "none": that made video lag the independent audio clock.
        // "inter" is the existing inter-frame-aware runtime policy.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_NIHAV_SKIP_MODE",
            "inter");

        // Preserve V72.4.2 audio behavior unchanged.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_HOST_AUDIO",
            "1");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_AUDIO_PREFER_FFPLAY",
            "1");
    }
}
