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

        // V72.4.3.2.8 REFERENCE_INTEGRITY_NO_SKIP
        // Preserve all temporal/reference frames in the NihAV decode chain.
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_SKIP_MODE", "none");

        Environment.SetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO", "1");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_AUDIO_PREFER_FFPLAY", "1");
    }
}
