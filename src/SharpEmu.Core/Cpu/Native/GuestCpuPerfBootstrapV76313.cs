// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.3.14.7.1: spread A/B was non-material; restore compact while isolating Bink ownership.

using System.Runtime.CompilerServices;

namespace SharpEmu.Core.Cpu.Native;

internal static class GuestCpuPerfBootstrapV76313
{
    internal const string Marker = "V76.3.13_GUEST_CPU_SCHEDULER";

    [ModuleInitializer]
    internal static void Initialize()
    {
        SetDefault("SHARPEMU_CPU_CACHE_AWARE", "1");
        SetDefault("SHARPEMU_CPU_CACHE_POLICY", "compact");
        SetDefault("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT", "16");
        SetDefault("SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT", "8");
        Console.Error.WriteLine(
            $"[{Marker}] cache_aware=1 policy=compact native_workers=16 renderer_workers=8 recovery=v7631471-bink-owner-rebase");
    }

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(name)))
        {
            Environment.SetEnvironmentVariable(name, value, EnvironmentVariableTarget.Process);
        }
    }
}
