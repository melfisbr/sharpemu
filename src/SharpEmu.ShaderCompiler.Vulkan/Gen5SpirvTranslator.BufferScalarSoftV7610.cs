// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.10: treat additional scalar control ops as no-ops; helpers for buffer soft-fail.

using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        /// <summary>
        /// Scalar opcodes that only affect scheduling / debug on RDNA and can
        /// safely become SPIR-V no-ops without changing results.
        /// </summary>
        private static bool IsScalarSchedulingNopV7610(string opcode) =>
            opcode is
                "SDelayAlu" or
                "SSleep" or
                "SSetvskip" or
                "SIncperflevel" or
                "SDecperflevel" or
                "SIcachenval" or
                "SWakeup" or
                "SBarrierInit" or // paired with join; full semantics later
                "SBarrierJoin" or
                "SCodeEnd" or
                "SWaitAlu";

        private bool TryEmitScalarSchedulingNopV7610(
            Gen5ShaderInstruction instruction,
            out string error)
        {
            error = string.Empty;
            if (!IsScalarSchedulingNopV7610(instruction.Opcode))
            {
                return false;
            }

            // Pure scheduling / power / cache hint — drop.
            return true;
        }
    }
}
