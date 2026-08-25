// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.1.7: F16/I64 compares, DPP16 expand, LDS 64-bit atomics, atomic aliases,
// graphics-stage barriers.

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static SpirvOp MapExtraFloatCompareV7617(string opcode) => opcode switch
        {
            "VCmpLtF16" or "VCmpxLtF16" => SpirvOp.FOrdLessThan,
            "VCmpEqF16" or "VCmpxEqF16" => SpirvOp.FOrdEqual,
            "VCmpLeF16" or "VCmpxLeF16" => SpirvOp.FOrdLessThanEqual,
            "VCmpGtF16" or "VCmpxGtF16" => SpirvOp.FOrdGreaterThan,
            "VCmpLgF16" or "VCmpxLgF16" => SpirvOp.FOrdNotEqual,
            "VCmpGeF16" or "VCmpxGeF16" => SpirvOp.FOrdGreaterThanEqual,
            "VCmpNeqF16" or "VCmpxNeqF16" => SpirvOp.FUnordNotEqual,
            "VCmpNltF16" or "VCmpxNltF16" => SpirvOp.FUnordGreaterThanEqual,
            "VCmpNleF16" or "VCmpxNleF16" => SpirvOp.FUnordGreaterThan,
            "VCmpNgtF16" or "VCmpxNgtF16" => SpirvOp.FUnordLessThanEqual,
            "VCmpNgeF16" or "VCmpxNgeF16" => SpirvOp.FUnordLessThan,
            "VCmpNlgF16" or "VCmpxNlgF16" => SpirvOp.FUnordEqual,
            _ => SpirvOp.Nop,
        };

        private static SpirvOp MapExtraIntegerCompareV7617(string opcode) => opcode switch
        {
            "VCmpEqI64" or "VCmpxEqI64" or "VCmpEqU64" or "VCmpxEqU64" => SpirvOp.IEqual,
            "VCmpNeI64" or "VCmpxNeI64" or "VCmpNeU64" or "VCmpxNeU64" => SpirvOp.INotEqual,
            "VCmpLtI64" or "VCmpxLtI64" => SpirvOp.SLessThan,
            "VCmpLeI64" or "VCmpxLeI64" => SpirvOp.SLessThanEqual,
            "VCmpGtI64" or "VCmpxGtI64" => SpirvOp.SGreaterThan,
            "VCmpGeI64" or "VCmpxGeI64" => SpirvOp.SGreaterThanEqual,
            "VCmpLtU64" or "VCmpxLtU64" => SpirvOp.ULessThan,
            "VCmpLeU64" or "VCmpxLeU64" => SpirvOp.ULessThanEqual,
            "VCmpGtU64" or "VCmpxGtU64" => SpirvOp.UGreaterThan,
            "VCmpGeU64" or "VCmpxGeU64" => SpirvOp.UGreaterThanEqual,
            _ => SpirvOp.Nop,
        };

        // V76.0.25: advertise only DPP16 controls that the RDNA2 lowering
        // below actually implements. Reserved values previously fell through to
        // src=self, silently corrupting cross-lane reductions instead of failing.
        private static bool IsSupportedDppControlV7617(uint control) =>
            control <= 0xFF ||
            control is >= 0x101 and <= 0x10F or
                >= 0x111 and <= 0x11F or
                >= 0x121 and <= 0x12F or
                0x140 or 0x141 or
                >= 0x150 and <= 0x15F or
                >= 0x160 and <= 0x16F;

        private static SpirvOp MapExtraLdsAtomicV7617(string opcode) => opcode switch
        {
            "DsAddU64" or "DsAddRtnU64" => SpirvOp.AtomicIAdd,
            "DsSubU64" or "DsSubRtnU64" => SpirvOp.AtomicISub,
            "DsMinI64" or "DsMinRtnI64" => SpirvOp.AtomicSMin,
            "DsMaxI64" or "DsMaxRtnI64" => SpirvOp.AtomicSMax,
            "DsMinU64" or "DsMinRtnU64" => SpirvOp.AtomicUMin,
            "DsMaxU64" or "DsMaxRtnU64" => SpirvOp.AtomicUMax,
            "DsAndB64" or "DsAndRtnB64" => SpirvOp.AtomicAnd,
            "DsOrB64" or "DsOrRtnB64" => SpirvOp.AtomicOr,
            "DsXorB64" or "DsXorRtnB64" => SpirvOp.AtomicXor,
            "DsWrxchgRtnB64" => SpirvOp.AtomicExchange,
            "DsCmpstB64" or "DsCmpstRtnB64" => SpirvOp.AtomicCompareExchange,
            "DsIncU64" or "DsIncRtnU64" => SpirvOp.AtomicIIncrement,
            "DsDecU64" or "DsDecRtnU64" => SpirvOp.AtomicIDecrement,
            _ => SpirvOp.Nop,
        };

        private static bool TryGetAtomicOpV7617(string name, out SpirvOp op)
        {
            op = name switch
            {
                "Swap" or "Xchg" or "Exchange" => SpirvOp.AtomicExchange,
                "Cmpswap" or "CmpSwap" or "CompareExchange" => SpirvOp.AtomicCompareExchange,
                "Add" => SpirvOp.AtomicIAdd,
                "Sub" => SpirvOp.AtomicISub,
                "Smin" or "SMin" => SpirvOp.AtomicSMin,
                "Umin" or "UMin" => SpirvOp.AtomicUMin,
                "Smax" or "SMax" => SpirvOp.AtomicSMax,
                "Umax" or "UMax" => SpirvOp.AtomicUMax,
                "And" => SpirvOp.AtomicAnd,
                "Or" => SpirvOp.AtomicOr,
                "Xor" => SpirvOp.AtomicXor,
                "Inc" => SpirvOp.AtomicIIncrement,
                "Dec" => SpirvOp.AtomicIDecrement,
                _ => SpirvOp.Nop,
            };
            return op != SpirvOp.Nop;
        }

        private void EmitStageBarrierV7617()
        {
            if (_stage == Gen5SpirvStage.Compute)
            {
                var wg = UInt(2);
                var sem = UInt(0x108);
                _module.AddStatement(SpirvOp.ControlBarrier, wg, wg, sem);
                return;
            }

            _module.AddStatement(SpirvOp.MemoryBarrier, UInt(1), UInt(0x48));
            if (_usesSubgroupOperations || _usesWaveControl)
            {
                var sg = UInt(3);
                _module.AddStatement(SpirvOp.ControlBarrier, sg, sg, UInt(0x48));
            }
        }
    }
}
