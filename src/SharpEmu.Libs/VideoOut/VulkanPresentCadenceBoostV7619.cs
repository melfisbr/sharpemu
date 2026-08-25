// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.1.9: default host present preference notes for 60 Hz.

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanPresentCadenceBoostV7619
{
    internal const string Marker = "V76.1.9_PRESENT_60";

    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Initialize()
    {
        Console.Error.WriteLine(
            $"[{Marker}] prefer SHARPEMU_HOST_TARGET_FPS=60 SHARPEMU_BINK_TARGET_FPS=60 " +
            "SHARPEMU_BINK_GUEST_TARGET_FPS=60");
    }
}
