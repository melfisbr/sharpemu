// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using Silk.NET.Vulkan;

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanPresentPolicyV7616
{
    internal static readonly bool LatestReadyEnabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_PRESENT_LATEST_READY"),
            "0",
            StringComparison.Ordinal);

    internal static readonly int LatestReadyThreshold =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_PRESENT_LATEST_READY_THRESHOLD"),
            out var threshold) && threshold >= 2
                ? Math.Clamp(threshold, 2, 8)
                : 3;

    internal static PresentModeKHR Select(
        ReadOnlySpan<PresentModeKHR> modes,
        bool vsync,
        bool frameGeneration,
        out string reason)
    {
        static bool Has(ReadOnlySpan<PresentModeKHR> available, PresentModeKHR mode)
        {
            foreach (var candidate in available)
            {
                if (candidate == mode)
                {
                    return true;
                }
            }
            return false;
        }

        var requested = Environment.GetEnvironmentVariable("SHARPEMU_VK_PRESENT_MODE")?
            .Trim().ToLowerInvariant();

        if (requested == "fifo")
        {
            reason = "forced-fifo";
            return PresentModeKHR.FifoKhr;
        }
        if (requested == "mailbox" && Has(modes, PresentModeKHR.MailboxKhr))
        {
            reason = "forced-mailbox";
            return PresentModeKHR.MailboxKhr;
        }
        if (requested == "immediate" && Has(modes, PresentModeKHR.ImmediateKhr))
        {
            reason = "forced-immediate";
            return PresentModeKHR.ImmediateKhr;
        }

        if ((!vsync || frameGeneration) && Has(modes, PresentModeKHR.ImmediateKhr))
        {
            reason = frameGeneration ? "auto-fg-immediate" : "auto-vsync-off-immediate";
            return PresentModeKHR.ImmediateKhr;
        }
        if (Has(modes, PresentModeKHR.MailboxKhr))
        {
            reason = "auto-mailbox";
            return PresentModeKHR.MailboxKhr;
        }

        reason = "fifo-fallback";
        return PresentModeKHR.FifoKhr;
    }
}
