// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.16.6: persistent defaults/runtime discovery for the Bink2 NIHAV path.
/// Environment variables remain overrides: this initializer only fills values
/// that the caller has not explicitly configured.
/// </summary>
internal static class BinkRuntimeBootstrapV6113166
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        // V72.4.3.2.31.4 RAD_REQUIRED_DEFAULT
        SetDefault("SHARPEMU_BINK_MODE", "rad");
        SetDefault("SHARPEMU_NIHAV_SINGLE_PASS", "1");
        SetDefault("SHARPEMU_NIHAV_STREAMING_SINGLE_PASS", "1");
        SetDefault("SHARPEMU_NIHAV_COLOR_MATRIX", "709");
        SetDefault("SHARPEMU_NIHAV_AUTO_RANGE", "0");
        SetDefault("SHARPEMU_BINK_YUV_FULL_RANGE", "1");
        SetDefault("SHARPEMU_NIHAV_CHUNK_SECONDS", "1");
        SetDefault("SHARPEMU_NIHAV_PREFETCH_FRAMES", "0");
        SetDefault("SHARPEMU_BINK_DIRECT_PRESENT_ONLY", "1");
        SetDefault("SHARPEMU_BINK_DIRECT_SWAP_RB", "0");

        // V61.20.0_MEDIA_CPU_MEMORY_COLOR_DEFAULTS
        // 1280x720 conversion is still close to the complete 33.3 ms budget on
        // the integrated Demon's Souls run. 960x540 has measured substantially
        // more headroom while VideoOut still scales to the host window.
        SetDefault("SHARPEMU_BINK_OUTPUT_MAX_WIDTH", "640");
        SetDefault("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT", "360");

        // Let the V70.4 fallback inspect the converted frame and choose the
        // alternate chroma order only when it actually reduces a green cast.
        // Do not force UV swap globally: other titles remain free to keep the
        // normal order, and explicit environment overrides still win.
        SetDefault("SHARPEMU_BINK_AUTO_UV_REPAIR", "1");

        // The current V70.4 direct tests are stable with full-range Bink YUV;
        // the defaults above also avoid deciding range from an all-black first frame.

        // The project already contains an adaptive producer throttle keyed to
        // real process working-set/private-memory pressure. Enable it by
        // default while boot movies overlap guest GPU initialization, then trim
        // released LOH/working-set pages and prioritize cross-queue sync work
        // for the bounded post-movie interval.
        SetDefault("SHARPEMU_BINK_THROTTLE_GUEST_GPU", "1");
        SetDefault("SHARPEMU_POST_BINK_TRIM_WORKING_SET", "1");
        SetDefault("SHARPEMU_POST_BINK_SYNC_PRIORITY", "1");

        // V61.21.0_NIHAV_REALTIME_PRODUCER
        // The integrated V61.20.0.1 run spends far more time waiting for the
        // external NIHAV producer than converting 960x540 frames. The decoder
        // otherwise launches NIHAV BelowNormal by default. Normal priority is
        // enough to avoid starving the producer without competing aggressively
        // with guest GPU/renderer work. Keep a hard nominal movie deadline so
        // boot videos do not stretch the guest startup timeline when the host
        // producer falls behind. Explicit environment overrides still win.
        // V72.4.3.2.22 NIHAV_REALTIME_PRIORITY
        // External nihav-tool is outside SharpEmu's temporary process-affinity
        // cap, so prioritize it and enforce nominal movie duration.
        // V72.4.3.2.25 HYBRID_REALTIME_STREAMING
        // V24 full-cache took 40+ seconds before the first movie and still did
        // not remove frame-truth artifacts. Return to live streaming while
        // keeping the safer CPU/audio work from later revisions.
        // V72.4.3.2.28 NIHAV_HIGH_PRIORITY
        SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "3");

        // V72.4.3.2.29 DEDICATED_DECODER_RUNTIME_DEFAULTS
        SetDefault("SHARPEMU_NIHAV_DEDICATED_LOGICAL_COUNT", "2");
        SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "0.9054");
        SetDefault("SHARPEMU_BINK_AUTO_BOOT_GRACE_MS", "1500");
        SetDefault("SHARPEMU_BINK_REALTIME_DEADLINE", "1");
        SetDefault("SHARPEMU_NIHAV_STREAM_FULL_CACHE", "0");
        SetDefault("SHARPEMU_NIHAV_STREAM_FULL_CACHE_TIMEOUT_SECONDS", "180");
        SetDefault("SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES", "60");
        SetDefault("SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS", "8");
        SetDefault("SHARPEMU_BINK_MAX_CATCHUP_SKIP", "0");

        // V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES
        //
        // Native/LTO NIHAV measured ~26.2 exported logo frames/s. A 60-frame
        // startup reservoir is enough to absorb the measured 12-second logo
        // deficit while preserving all decoded frames in order.
        //
        // Keep the validated V17 Q14 path active and apply the V27 U/V-only
        // boundary repair before conversion.
        SetDefault("SHARPEMU_BINK_FFMPEG_COLOR", "0");
        SetDefault("SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION", "1");
        SetDefault("SHARPEMU_BINK_CHROMA_DEBLOCK", "1");
        SetDefault("SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD", "24");
        SetDefault("SHARPEMU_BINK_CHROMA_BLOCK_BIAS_THRESHOLD", "4");
        SetDefault("SHARPEMU_BINK_CHROMA_BLOCK_NEIGHBOUR_SPREAD", "12");
        SetDefault("SHARPEMU_BINK_CHROMA_BLOCK_BIAS_STRENGTH", "75");
        SetDefault("SHARPEMU_DS_INTRO_EXTERNAL_AUDIO", "1");

        if (string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_TOOL")))
        {
            var discovered = DiscoverNihavTool();
            if (discovered is not null)
            {
                Environment.SetEnvironmentVariable(
                    "SHARPEMU_NIHAV_TOOL",
                    discovered,
                    EnvironmentVariableTarget.Process);

                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.nihav_auto_discovered tool='{discovered}'");
            }
        }
    }

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)))
        {
            Environment.SetEnvironmentVariable(
                name,
                value,
                EnvironmentVariableTarget.Process);
        }
    }

    private static string? DiscoverNihavTool()
    {
        var executableNames = OperatingSystem.IsWindows()
            ? new[] { "nihav-tool.exe", "nihav_tool.exe" }
            : new[] { "nihav-tool", "nihav_tool" };

        foreach (var executableName in executableNames)
        {
            var deployed = Path.Combine(
                AppContext.BaseDirectory,
                "plugins",
                "bink2",
                executableName);
            if (File.Exists(deployed))
            {
                return Path.GetFullPath(deployed);
            }
        }

        // Local developer builds live below:
        // <repo>\artifacts\bin\Debug\net10.0\win-x64.
        // Walk upwards instead of hard-coding a repository path.
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; directory is not null && depth < 10; depth++)
        {
            foreach (var executableName in executableNames)
            {
                var candidate = Path.Combine(
                    directory.FullName,
                    ".sharpemu-tools",
                    "bink2",
                    "src",
                    "nihav",
                    "nihav-tool",
                    "target",
                    "release",
                    executableName);

                if (File.Exists(candidate))
                {
                    return Path.GetFullPath(candidate);
                }
            }

            directory = directory.Parent;
        }

        return null;
    }
}
