// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.IO;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// V31.7.22: prevents the pre-PlayStation-Studios guest scanout from resurfacing
/// when the embedded RAD child is removed.
///
/// SubmitHostMovieHandoffBlackV11() already writes an opaque black handoff frame,
/// but TryTakePresentation() gives the retained guest-flip FIFO priority over
/// _latestPresentation.  A completed guest flip captured before the handoff can
/// therefore win immediately after the RAD child is hidden and expose the old
/// "Sony Interactive Entertainment presents" scanout again.
///
/// The barrier is deliberately narrow: it arms only for ps_studios_logo.bk2,
/// drops guest presentations already pending at that exact handoff, and keeps
/// the black handoff visible until a guest presentation depends on work or an
/// ordered flip that was enqueued after the handoff floor.
/// </summary>
internal static unsafe partial class VulkanVideoPresenter
{
    private static bool _postStudiosFreshGuestBarrierV31722;
    private static long _postStudiosWorkFloorV31722;
    private static long _postStudiosFlipFloorV31722;
    private static long _postStudiosArmTickV31722;
    private static long _postStudiosSuppressedV31722;
    private static Presentation? _postStudiosBlackPresentationV31722;

    private static void ResetPostStudiosFreshGuestBarrierLockedV31722()
    {
        _postStudiosFreshGuestBarrierV31722 = false;
        _postStudiosWorkFloorV31722 = 0;
        _postStudiosFlipFloorV31722 = 0;
        _postStudiosArmTickV31722 = 0;
        _postStudiosSuppressedV31722 = 0;
        _postStudiosBlackPresentationV31722 = null;
    }

    private static void ArmPostStudiosFreshGuestBarrierLockedV31722(
        string movieName)
    {
        var fileName = Path.GetFileName(movieName ?? string.Empty);
        if (!string.Equals(
                fileName,
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_POST_STUDIOS_FRESH_FRAME_BARRIER"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }

        if (_latestPresentation is not { } black)
        {
            return;
        }

        var dropped = _pendingGuestImagePresentations.Count;
        _pendingGuestImagePresentations.Clear();

        _postStudiosFreshGuestBarrierV31722 = true;
        _postStudiosWorkFloorV31722 = _enqueuedGuestWorkSequence;
        _postStudiosFlipFloorV31722 = _orderedGuestFlipVersionSequence;
        _postStudiosArmTickV31722 = Environment.TickCount64;
        _postStudiosSuppressedV31722 = dropped;
        _postStudiosBlackPresentationV31722 = black;

        Console.Error.WriteLine(
            "[V31.7.22][POST_STUDIOS_FRESH_FRAME] armed " +
            $"file='{fileName}' black_seq={black.Sequence} " +
            $"guest_work_floor={_postStudiosWorkFloorV31722} " +
            $"flip_floor={_postStudiosFlipFloorV31722} " +
            $"pending_guest_frames_dropped={dropped} " +
            "policy=black-until-post-handoff-guest-work");
    }

    private static void ApplyPostStudiosFreshGuestBarrierLockedV31722(
        long presentedSequence)
    {
        if (!_postStudiosFreshGuestBarrierV31722)
        {
            return;
        }

        while (_pendingGuestImagePresentations.Count > 0)
        {
            var pending = _pendingGuestImagePresentations.Peek();
            if (IsPostStudiosFreshGuestPresentationV31722(pending))
            {
                if (IsGuestWorkCompletedLocked(
                        pending.RequiredGuestWorkSequence))
                {
                    ReleasePostStudiosFreshGuestBarrierLockedV31722(
                        pending,
                        "pending-fresh");
                }
                return;
            }

            _pendingGuestImagePresentations.Dequeue();
            TracePostStudiosSuppressedGuestPresentationV31722(
                pending,
                "pending-stale");
        }

        if (_latestPresentation is not { } latest ||
            _postStudiosBlackPresentationV31722 is not { } black)
        {
            return;
        }

        if (latest.Sequence == black.Sequence)
        {
            return;
        }

        if (IsPostStudiosFreshGuestPresentationV31722(latest))
        {
            if (IsGuestWorkCompletedLocked(
                    latest.RequiredGuestWorkSequence))
            {
                ReleasePostStudiosFreshGuestBarrierLockedV31722(
                    latest,
                    "latest-fresh");
            }
            return;
        }

        // A legacy/direct scanout can be published after the handoff using old
        // guest work.  Re-issue the already-created opaque black frame with a
        // sequence newer than both the stale candidate and the last frame the
        // presenter consumed, so TryTakePresentation cannot expose that scanout.
        var blackSequence = Math.Max(
            Math.Max(latest.Sequence, presentedSequence),
            black.Sequence) + 1;
        var refreshedBlack = black with { Sequence = blackSequence };
        _latestPresentation = refreshedBlack;
        _postStudiosBlackPresentationV31722 = refreshedBlack;

        TracePostStudiosSuppressedGuestPresentationV31722(
            latest,
            "latest-stale-reblack");
    }

    private static bool IsPostStudiosFreshGuestPresentationV31722(
        Presentation presentation)
    {
        if (_postStudiosBlackPresentationV31722 is { } black &&
            presentation.Sequence <= black.Sequence)
        {
            return false;
        }

        // Host-owned BGRA frames (including later Bink handoff blacks) do
        // not prove that the guest has advanced beyond the stale scanout.
        // Bink-exclusive presentation is handled before the guest FIFO, so
        // keep this barrier tied strictly to fresh guest GPU work/flip.
        if (presentation.Pixels is not null)
        {
            return false;
        }

        if (presentation.GuestImageVersion > 0 &&
            presentation.GuestImageVersion >
                _postStudiosFlipFloorV31722)
        {
            return true;
        }

        return presentation.RequiredGuestWorkSequence >
               _postStudiosWorkFloorV31722;
    }

    private static void ReleasePostStudiosFreshGuestBarrierLockedV31722(
        Presentation presentation,
        string reason)
    {
        var elapsed = _postStudiosArmTickV31722 > 0
            ? Environment.TickCount64 - _postStudiosArmTickV31722
            : 0;

        Console.Error.WriteLine(
            "[V31.7.22][POST_STUDIOS_FRESH_FRAME] released " +
            $"reason={reason} seq={presentation.Sequence} " +
            $"guest_work={presentation.RequiredGuestWorkSequence} " +
            $"guest_image_version={presentation.GuestImageVersion} " +
            $"wait_ms={elapsed} suppressed={_postStudiosSuppressedV31722}");

        _postStudiosFreshGuestBarrierV31722 = false;
        _postStudiosBlackPresentationV31722 = null;
    }

    private static void TracePostStudiosSuppressedGuestPresentationV31722(
        Presentation presentation,
        string reason)
    {
        var count = ++_postStudiosSuppressedV31722;
        if (count <= 8 || (count & (count - 1)) == 0)
        {
            Console.Error.WriteLine(
                "[V31.7.22][POST_STUDIOS_FRESH_FRAME] suppressed " +
                $"n={count} reason={reason} seq={presentation.Sequence} " +
                $"guest_work={presentation.RequiredGuestWorkSequence} " +
                $"guest_image_version={presentation.GuestImageVersion} " +
                $"guest_addr=0x{presentation.GuestImageAddress:X16}");
        }
    }
}
