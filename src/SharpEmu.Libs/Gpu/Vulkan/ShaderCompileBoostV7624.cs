// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Gpu.Vulkan;

internal static class ShaderCompileBoostV7624
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (string.IsNullOrEmpty(
                Environment.GetEnvironmentVariable("SHARPEMU_VK_PARALLEL_STAGE_COMPILE")))
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_VK_PARALLEL_STAGE_COMPILE",
                "1",
                EnvironmentVariableTarget.Process);
        }

        Console.Error.WriteLine(
            "[SHADER-BOOST][V76.2.4] parallel_stage=" +
            (Environment.GetEnvironmentVariable("SHARPEMU_VK_PARALLEL_STAGE_COMPILE") ?? "?") +
            " prewarm_max=" +
            (Environment.GetEnvironmentVariable("SHARPEMU_SPIRV_PREWARM_MAX") ?? "?"));
    }
}
