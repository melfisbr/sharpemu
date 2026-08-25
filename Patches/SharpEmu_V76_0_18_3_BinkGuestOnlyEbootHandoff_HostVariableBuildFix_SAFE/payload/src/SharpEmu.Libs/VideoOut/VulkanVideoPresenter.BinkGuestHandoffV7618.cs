// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.IO;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// V76.0.18 guest-only Bink close handoff. A title Bink lifetime ends when the
/// guest closes its final .bk2 fd; no host black frame, decoder completion shim
/// or external-player transition is allowed to own that boundary.
/// </summary>
internal static unsafe partial class VulkanVideoPresenter
{
    internal static void CompleteGuestBinkHandoffV7618(
        string? moviePath,
        long epoch)
    {
        lock (_gate)
        {
            // Clear host-only movie state without touching _latestPresentation
            // or the guest presentation FIFO. The eboot's next/already-rendered
            // guest frame remains eligible to be presented immediately.
            ResetPostStudiosFreshGuestBarrierLockedV31722();
            _binkExclusiveFrame = null;
            _binkExclusiveUntilTick = 0;
            _binkExclusiveWasActive = false;
            _naturalBinkDescriptorlessDirectFallbackActive = false;
            _binkSessionActive = false;
            _binkSessionCompleted = true;
            _binkSessionPath = null;
            _binkSessionStartTick = 0;
            _binkSessionEndTick = 0;
            _binkSessionBaseSerial = -1;

            _hostMovieFramePixels = null;
            _hostMovieFrameWidth = 0;
            _hostMovieFrameHeight = 0;
            _hostMovieFrameSerial = -1;
            _hostMovieFramePath = null;
            _hostMovieLumaTextureAddress = 0;
            _hostMovieChromaTextureAddress = 0;
        }

        Console.Error.WriteLine(
            "[BINK-GUEST][V76.0.18][EBOOT-HANDOFF] " +
            $"file='{Path.GetFileName(moviePath ?? string.Empty)}' epoch={epoch} " +
            "action=guest-close-continue no_black=True no_host_wait=True " +
            "guest_presentations_preserved=True");
    }
}
