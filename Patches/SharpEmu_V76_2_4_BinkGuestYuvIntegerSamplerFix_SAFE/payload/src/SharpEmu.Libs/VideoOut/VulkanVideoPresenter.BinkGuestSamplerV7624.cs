// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;
using SharpEmu.Libs.Gpu;

namespace SharpEmu.Libs.VideoOut;

/// <summary>
/// V76.2.4: final guest Bink Y/UV planes are integer images (R8Uint/R8G8Uint).
/// Vulkan integer sampled images must not be paired with linear filtering.
/// Preserve the guest-produced integer storage/view and normalize only the
/// sampler used by the final tile-5 Y/UV presentation path to nearest/no-mip.
/// </summary>
internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        private static readonly bool _binkIntegerNearestEnabledV7624 =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_INTEGER_NEAREST"),
                "0",
                StringComparison.Ordinal);

        private static long _binkIntegerSamplerNormalizeCountV7624;

        private static GuestSampler NormalizeGuestBinkIntegerSamplerV7624(
            GuestSampler sampler,
            uint planeFormat,
            ulong address)
        {
            if (!_binkIntegerNearestEnabledV7624)
            {
                return sampler;
            }

            var guestMag = DecodeSamplerMagFilter(sampler);
            var guestMin = DecodeSamplerMinFilter(sampler);
            var guestMip = DecodeSamplerMipFilter(sampler);

            const uint filterMask =
                (0x3u << 20) | // MAG_FILTER
                (0x3u << 22) | // MIN_FILTER
                (0x3u << 26);  // MIP_FILTER

            var normalized = sampler with
            {
                Word2 = sampler.Word2 & ~filterMask,
            };

            var count = Interlocked.Increment(
                ref _binkIntegerSamplerNormalizeCountV7624);
            if (count <= 64 || (count & (count - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[BINK-GUEST][V76.2.4][YUV-SAMPLER] " +
                    $"count={count} plane={(planeFormat == 1 ? "Y" : "UV")} " +
                    $"addr=0x{address:X16} " +
                    $"guest_mag={guestMag} guest_min={guestMin} guest_mip={guestMip} " +
                    "host_mag=nearest host_min=nearest host_mip=nearest " +
                    $"changed={(normalized.Word2 != sampler.Word2 ? 1 : 0)} " +
                    "reason=integer-yuv-sampling");
            }

            return normalized;
        }
    }
}
