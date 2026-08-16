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
        SetDefault("SHARPEMU_NIHAV_SINGLE_PASS", "1");
        SetDefault("SHARPEMU_NIHAV_STREAMING_SINGLE_PASS", "1");
        SetDefault("SHARPEMU_NIHAV_COLOR_MATRIX", "709");
        SetDefault("SHARPEMU_NIHAV_UV_SWAP", "0");
        SetDefault("SHARPEMU_NIHAV_AUTO_RANGE", "1");
        SetDefault("SHARPEMU_BINK_YUV_FULL_RANGE", "0");
        SetDefault("SHARPEMU_NIHAV_CHUNK_SECONDS", "1");
        SetDefault("SHARPEMU_NIHAV_PREFETCH_FRAMES", "0");
        SetDefault("SHARPEMU_BINK_DIRECT_PRESENT_ONLY", "1");
        SetDefault("SHARPEMU_BINK_DIRECT_SWAP_RB", "0");

        // V61.19.0_MEDIA_GPU_STABILITY_DEFAULTS
        // 4K -> 1080p conversion was consistently slower than a 30 fps frame
        // budget on the Demon's Souls NIHAV path. 720p has already demonstrated
        // real-time conversion in the same runtime and is upscaled by VideoOut.
        SetDefault("SHARPEMU_BINK_OUTPUT_MAX_WIDTH", "1280");
        SetDefault("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT", "720");

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
