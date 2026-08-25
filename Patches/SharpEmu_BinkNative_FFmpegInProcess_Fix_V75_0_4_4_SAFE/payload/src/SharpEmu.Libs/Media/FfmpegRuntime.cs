// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.IO;
using FFmpeg.AutoGen;

namespace SharpEmu.Libs.Media;
internal static class FfmpegRuntime
{
    // SHARPEMU_BINK_FFMPEG_INPROCESS_V75_0_4_4
    private static readonly object _gate = new();
    private static bool _initialized;

    internal static string RuntimeRoot
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable(
                "SHARPEMU_FFMPEG_CORE_ROOT");
            if (!string.IsNullOrWhiteSpace(configured))
            {
                return Path.GetFullPath(configured);
            }

            return Path.Combine(AppContext.BaseDirectory, "plugins");
        }
    }

    internal static bool IsRuntimeCandidatePresent
    {
        get
        {
            var root = RuntimeRoot;
            return File.Exists(Path.Combine(root, "avcodec-61.dll")) &&
                   File.Exists(Path.Combine(root, "avformat-61.dll")) &&
                   File.Exists(Path.Combine(root, "avutil-59.dll")) &&
                   File.Exists(Path.Combine(root, "swscale-8.dll")) &&
                   File.Exists(Path.Combine(root, "swresample-5.dll"));
        }
    }

    internal static void EnsureInitialized()
    {
        if (_initialized)
        {
            return;
        }

        lock (_gate)
        {
            if (_initialized)
            {
                return;
            }

            var runtimeRoot = RuntimeRoot;
            ffmpeg.RootPath = runtimeRoot;
            DynamicallyLoadedBindings.Initialize();
            _initialized = true;

            Console.Error.WriteLine(
                "[BINK-FFMPEG][V75.0.4.4] runtime_initialized " +
                $"root='{runtimeRoot}' candidate={IsRuntimeCandidatePresent}");
        }
    }
}
