// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.3: restore reliable Bink decode path.
//
// Log evidence (Demon's Souls / similar):
//   [BINK-GUEST] guest-bink-active + PERF fps≈1.8
//   SEMANTIC_WAIT 120–620ms, SLOW_WAIT_PRODUCER 1.4–2.0s
// Guest-owned GPU decode stays active but is far too slow; host decoder was
// hard-blocked by BinkGuestOwnedRuntimeV7600.Enabled (needs
// SHARPEMU_BINK_ALLOW_HOST_DECODER=1). This policy enables hybrid host decode
// by default unless SHARPEMU_BINK_FORCE_GUEST=1.

using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

internal static class BinkDecodePolicyV7623
{
    internal const string Marker = "V76.2.3_BINK_HYBRID_HOST";

    /// <summary>
    /// When true, host RAD/Nihav paths may run (GuestOwnedRuntime.Enabled=false).
    /// </summary>
    // V76.0.25: PS5 title Bink2 is guest-owned. Do not let the legacy
    // V76.2.3 hybrid policy re-enable FFmpeg/NihAV/RAD host takeover.
    internal static bool AllowHostDecoder => false;

    [ModuleInitializer]
    internal static void Initialize()
    {
        if (!AllowHostDecoder)
        {
            Console.Error.WriteLine(
                $"[{Marker}] force_guest=1 host_decoder=off (GPU guest path only)");
            return;
        }

        // Process-scoped: flips GuestOwnedRuntime.Enabled to false on next read.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_ALLOW_HOST_DECODER",
            "1",
            EnvironmentVariableTarget.Process);

        // Prefer realtime host audio+video for boot movies.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_HOST_AUDIO",
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO") ?? "1",
            EnvironmentVariableTarget.Process);

        // Do not hold first visual for 180ms when host path is active.
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
