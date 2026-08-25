// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.1.8: extra soft-fail / compare coverage for remaining hard paths
// (global memory, storage image, scalar compares, scalar 64-bit).

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static SpirvOp MapExtraScalarCompareV7618(string opcode) => opcode switch
        {
            "SCmpEqI64" or "SCmpEqU64" => SpirvOp.IEqual,
            "SCmpLgI64" or "SCmpLgU64" => SpirvOp.INotEqual,
            "SCmpLtI64" => SpirvOp.SLessThan,
            "SCmpLeI64" => SpirvOp.SLessThanEqual,
            "SCmpGtI64" => SpirvOp.SGreaterThan,
            "SCmpGeI64" => SpirvOp.SGreaterThanEqual,
            "SCmpLtU64" => SpirvOp.ULessThan,
            "SCmpLeU64" => SpirvOp.ULessThanEqual,
            "SCmpGtU64" => SpirvOp.UGreaterThan,
            "SCmpGeU64" => SpirvOp.UGreaterThanEqual,
            _ => SpirvOp.Nop,
        };
    }
}
