// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.5: public structural-validation seam for persisted SPIR-V cache entries.

using System;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    public static bool TryValidateBinaryV7605(
        ReadOnlySpan<byte> spirv,
        out string error) =>
        SpirvStructuralValidator.TryValidate(spirv, out error);
}
