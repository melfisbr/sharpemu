// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Libs.Gpu;
using SharpEmu.Libs.Media;
using Silk.NET.Vulkan;
using System;
using System.Threading;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// V76.0.24 keeps Bink2 decode and storage ownership entirely on the guest GPU,
/// while exposing the final byte Y/UV planes through normalized sampled views.
///
/// Bluepoint's Bink composite descriptors are reported as format 1/3 with
/// NumberType=4.  That UINT identity is required for ImageLoad/ImageStore during
/// guest compute decode.  The composite/sample side, however, consumes the same
/// bytes as normalized YUV.  Guest images are created MUTABLE_FORMAT, therefore
/// R8Uint -> R8Unorm and R8G8Uint -> R8G8Unorm are legal compatible views of the
/// same VkImage; no CPU copy and no host decoder are introduced.
/// </summary>
internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        private static readonly bool _v7624NormalizedBinkSampleViewEnabled =
            !string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_YUV_NORMALIZED_SAMPLE_VIEW"),
                "0",
                StringComparison.OrdinalIgnoreCase);

        private long _v7624NormalizedBinkSampleViewTraceCount;

        private Format GetGuestBinkNormalizedSampleViewFormatV7624(
            GuestDrawTexture texture,
            Format storageFormat)
        {
            if (!_v7624NormalizedBinkSampleViewEnabled ||
                !IsFinalGuestBinkYuvPlaneV7602(texture))
            {
                return storageFormat;
            }

            var sampledFormat = storageFormat switch
            {
                Format.R8Uint => Format.R8Unorm,
                Format.R8G8Uint => Format.R8G8Unorm,
                _ => storageFormat,
            };

            if (sampledFormat == storageFormat)
            {
                return storageFormat;
            }

            // Every guest image used by this path is created with
            // VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT. Keep a defensive compatibility
            // check so an unexpected format never escapes into vkCreateImageView.
            if (!IsCompatibleViewFormat(storageFormat, sampledFormat))
            {
                return storageFormat;
            }

            var trace = Interlocked.Increment(
                ref _v7624NormalizedBinkSampleViewTraceCount);
            if (trace <= 32 || (trace & (trace - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[BINK-GUEST][V76.0.24][YUV-SAMPLE-VIEW] " +
                    $"count={trace} plane={(texture.Format == 1 ? "Y" : "UV")} " +
                    $"addr=0x{texture.Address:X16} size={texture.Width}x{texture.Height} " +
                    $"storage={storageFormat} sampled={sampledFormat} " +
                    "same_image=True cpu_copy=False host_decoder=False");
            }

            return sampledFormat;
        }
    }
}
