// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.8: preserve Bink2 temporal references.
/// Frame-truth showed structural corruption already exists in decoded luma.
/// The 640x360 read+conversion path is below the 30-fps frame budget, so
/// decoder-level frame skipping is no longer justified.
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

        Environment.SetEnvironmentVariable("SHARPEMU_BINK_REALTIME_DEADLINE", "0");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_COLOR", "0");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_UV_SWAP", "0");
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_UV_SWAP", "0");
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_AUTO_RANGE", "0");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_OUTPUT_MAX_WIDTH", "640");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT", "360");

        // SHARPEMU_V74_0_95_1_UI_BINK_DECODE_CAP
        // SHARPEMU_V74_0_95_2_2_3_UI_BINK_720P_COMPAT
        // Keep fullscreen/boot movie defaults untouched. The mutable Presenter
        // no longer exposes the old BGRA->YUV anchor, so this revision raises UI
        // quality conservatively to 1280x720 without changing its pixel-layout API.
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_UI_BINK_OUTPUT_MAX_WIDTH")))
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_DS_UI_BINK_OUTPUT_MAX_WIDTH",
                "1280");
        }
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_UI_BINK_OUTPUT_MAX_HEIGHT")))
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_DS_UI_BINK_OUTPUT_MAX_HEIGHT",
                "720");
        }

        // V72.4.3.2.8 REFERENCE_INTEGRITY_NO_SKIP
        // Preserve all temporal/reference frames in the NihAV decode chain.
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_SKIP_MODE", "none");

        Environment.SetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO", "1");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_AUDIO_PREFER_FFPLAY", "1");
    }
}
