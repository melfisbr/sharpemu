// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Libs.Gpu;
using SharpEmu.Libs.Media;
using System.Collections.Generic;
using System.Threading;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// V76.0.12 guest-owned Bink YUV producer ownership.
///
/// Final Bink Y/UV planes are GPU-produced ping-pong images.  A Vulkan image
/// that was initialized by a previous .bk2 session is not a valid producer for
/// the next movie even when the guest reuses the same virtual address.
/// </summary>
internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        private readonly Dictionary<(ulong Address, ulong ImageHandle), long>
            _v7612GuestBinkYuvProducerEpochs = new();
        private long _v7612TrackedGuestBinkEpoch;
        private long _v7612GuestBinkProducerStampCount;
        private long _v7612GuestBinkStaleProducerRejectCount;
        private long _v7612GuestBinkCpuUploadSuppressCount;

        private void RefreshGuestBinkYuvEpochV7612()
        {
            if (!BinkGuestOwnedRuntimeV7600.YuvSessionEpochEnabled)
            {
                return;
            }

            var epoch = BinkGuestOwnedRuntimeV7600.ActiveSessionEpoch;
            if (epoch <= 0 || epoch == _v7612TrackedGuestBinkEpoch)
            {
                return;
            }

            _v7612GuestBinkYuvProducerEpochs.Clear();
            _v7612TrackedGuestBinkEpoch = epoch;
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.0.12][YUV-EPOCH] " +
                $"epoch={epoch} action=reset-producer-registry");
        }

        private bool IsCurrentGuestBinkYuvProducerV7612(
            GuestImageResource candidate)
        {
            if (!BinkGuestOwnedRuntimeV7600.YuvSessionEpochEnabled)
            {
                return true;
            }

            RefreshGuestBinkYuvEpochV7612();
            var epoch = BinkGuestOwnedRuntimeV7600.ActiveSessionEpoch;
            if (epoch <= 0)
            {
                return false;
            }

            if (_v7612GuestBinkYuvProducerEpochs.TryGetValue(
                    (candidate.Address, candidate.Image.Handle),
                    out var producerEpoch) &&
                producerEpoch == epoch)
            {
                return true;
            }

            // V76.2.3: if the image was written this session (generation>0),
            // accept it â€” missing MarkGuestBinkYuvProducer caused false rejects
            // and black Bink output while GPU work continued slowly.
            if (candidate.ContentGeneration > 0)
            {
                _v7612GuestBinkYuvProducerEpochs[
                    (candidate.Address, candidate.Image.Handle)] = epoch;
                return true;
            }

            var reject = Interlocked.Increment(
                ref _v7612GuestBinkStaleProducerRejectCount);
            if (reject <= 32 || (reject & (reject - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[BINK-GUEST][V76.0.12][YUV-PRODUCER-REJECT] " +
                    $"count={reject} addr=0x{candidate.Address:X16} " +
                    $"image=0x{candidate.Image.Handle:X16} " +
                    $"producer_epoch={producerEpoch} active_epoch={epoch} " +
                    $"generation={candidate.ContentGeneration} " +
                    "reason=not-written-in-current-bink-session");
            }

            return false;
        }

        private void MarkGuestBinkYuvProducerV7612(TextureResource texture)
        {
            if (!BinkGuestOwnedRuntimeV7600.YuvSessionEpochEnabled ||
                !IsFinalGuestBinkYuvStorageV7602(texture) ||
                texture.GuestImage is not { } guestImage)
            {
                return;
            }

            RefreshGuestBinkYuvEpochV7612();
            var epoch = BinkGuestOwnedRuntimeV7600.ActiveSessionEpoch;
            if (epoch <= 0)
            {
                return;
            }

            var key = (texture.Address, guestImage.Image.Handle);
            var changed =
                !_v7612GuestBinkYuvProducerEpochs.TryGetValue(
                    key,
                    out var previousEpoch) ||
                previousEpoch != epoch;
            _v7612GuestBinkYuvProducerEpochs[key] = epoch;

            if (!changed)
            {
                return;
            }

            var stamp = Interlocked.Increment(
                ref _v7612GuestBinkProducerStampCount);
            if (stamp <= 32 || (stamp & (stamp - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[BINK-GUEST][V76.0.12][YUV-PRODUCER] " +
                    $"count={stamp} epoch={epoch} " +
                    $"addr=0x{texture.Address:X16} " +
                    $"image=0x{guestImage.Image.Handle:X16} " +
                    $"generation={guestImage.ContentGeneration} " +
                    "source=gpu-storage-write");
            }
        }

        private bool ShouldSuppressGuestBinkStorageCpuUploadV7612(
            GuestDrawTexture texture)
        {
            if (!IsFinalGuestBinkYuvStorageV7602(texture))
            {
                return false;
            }

            var count = Interlocked.Increment(
                ref _v7612GuestBinkCpuUploadSuppressCount);
            if (count <= 16 || (count & (count - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[BINK-GUEST][V76.0.12][YUV-STORAGE-CPU-UPLOAD] " +
                    $"count={count} plane={(texture.Format == 1 ? "Y" : "UV")} " +
                    $"addr=0x{texture.Address:X16} " +
                    $"size={texture.Width}x{texture.Height} " +
                    "action=suppress reason=gpu-authoritative-producer");
            }

            return true;
        }
    }
}
