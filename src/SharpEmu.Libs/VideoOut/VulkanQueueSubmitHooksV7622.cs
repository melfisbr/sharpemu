// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.2/V76.0.26: fence-paired post-submit hooks; no pre-submit blocking.

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanQueueSubmitHooksV7622
{
    internal static void NoteGraphicsSubmit() =>
        VulkanQueueOptimizerV7622.OnGraphicsSubmitted();

    internal static void NoteComputeSubmit() =>
        VulkanQueueOptimizerV7622.OnComputeSubmitted();

    internal static void NoteSubmitComplete() =>
        VulkanQueueOptimizerV7622.OnSubmitComplete();

    internal static void NotePresented() =>
        VulkanQueueOptimizerV7622.OnPresented();
}
