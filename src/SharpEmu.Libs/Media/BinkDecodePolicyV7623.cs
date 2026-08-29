// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.5: restore reliable Bink decode path for Demon's Souls boot logos.
//
// Log evidence (PPSA01341):
//   [BINK-GUEST] SESSION decode_owner=guest + STRICT-COMPUTE dispatches
//   [YUV-STORAGE-CPU-UPLOAD] action=suppress reason=gpu-authoritative-producer
//   Screen presents rainbow noise at ~2–3 FPS (guest planes not valid)
//
// Guest GPU decode remains available via SHARPEMU_BINK_FORCE_GUEST=1.
// Default for Demon's Souls: host hybrid (see BinkGuestOwnedRuntimeV7600).

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

internal static class BinkDecodePolicyV7623
{
    internal const string Marker = "V76.2.5.1_BINK_HYBRID_HOST";

    /// <summary>
    /// When true, host RAD/Nihav paths may run (GuestOwnedRuntime.Enabled=false).
    /// Mirrors BinkGuestOwnedRuntimeV7600.HostBinkDecoderAllowed.
    /// </summary>
    internal static bool AllowHostDecoder =>
        BinkGuestOwnedRuntimeV7600.HostBinkDecoderAllowed;

    [ModuleInitializer]
    internal static void Initialize()
    {
        if (!AllowHostDecoder)
        {
            Console.Error.WriteLine(
                $"[{Marker}] force_guest=1 host_decoder=off (GPU guest path only)");
            return;
        }

        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_ALLOW_HOST_DECODER",
            "1",
            EnvironmentVariableTarget.Process);

        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_HOST_AUDIO",
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO") ?? "1",
            EnvironmentVariableTarget.Process);

        if (string.IsNullOrEmpty(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_FIRST_VISUAL_HOLD_MS")))
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_BINK_FIRST_VISUAL_HOLD_MS",
                "16",
                EnvironmentVariableTarget.Process);
        }

        Console.Error.WriteLine(
            $"[{Marker}] host_decoder=on hybrid=1 " +
            "set SHARPEMU_BINK_FORCE_GUEST=1 to restore pure guest GPU decode");
    }
}
