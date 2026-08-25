// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.2: thin hooks so partial presenter code can opt into the optimizer
// without rewriting submit paths.

namespace SharpEmu.Libs.VideoOut;

internal static class VulkanQueueSubmitHooksV7622
{
    internal static void NoteGraphicsSubmit() =>
        VulkanQueueOptimizerV7622.BeforeGraphicsSubmit();

    internal static void NoteComputeSubmit() =>
        VulkanQueueOptimizerV7622.BeforeComputeSubmit();

    internal static void NoteSubmitComplete() =>
        VulkanQueueOptimizerV7622.OnSubmitComplete();

    internal static void NotePresented() =>
        VulkanQueueOptimizerV7622.OnPresented();
}
