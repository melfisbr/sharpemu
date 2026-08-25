// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.1: F16 ALU, V_READLANE, V_MAD_I32_I24, V_SUB_F64, V_PACK_B32_F16.

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private uint F16BinaryV7621(Gen5ShaderInstruction instruction, SpirvOp op)
        {
            var a = Bitcast(_floatType, EmitHalfToFloat(
                BitwiseAnd(GetRawSource(instruction, 0), UInt(0xFFFF))));
            var b = Bitcast(_floatType, EmitHalfToFloat(
                BitwiseAnd(GetRawSource(instruction, 1), UInt(0xFFFF))));
            var r = _module.AddInstruction(op, _floatType, a, b);
            return EmitFloatToHalf(Bitcast(_uintType, r));
        }

        private bool TryEmitExtraVectorOpcodeV7621(
            Gen5ShaderInstruction instruction,
            uint destination,
            out uint result,
            out string error)
        {
            result = 0;
            error = string.Empty;

            switch (instruction.Opcode)
            {
                case "VAddF16":
                    result = F16BinaryV7621(instruction, SpirvOp.FAdd);
                    return true;
                case "VSubF16":
                case "VSubrevF16":
                {
                    var a = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 0), UInt(0xFFFF))));
                    var b = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 1), UInt(0xFFFF))));
                    if (instruction.Opcode == "VSubrevF16")
                    {
                        (a, b) = (b, a);
                    }

                    result = EmitFloatToHalf(Bitcast(
                        _uintType,
                        _module.AddInstruction(SpirvOp.FSub, _floatType, a, b)));
                    return true;
                }
                case "VMulF16":
                    result = F16BinaryV7621(instruction, SpirvOp.FMul);
                    return true;
                case "VMaxF16":
                {
                    var a = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 0), UInt(0xFFFF))));
                    var b = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 1), UInt(0xFFFF))));
                    result = EmitFloatToHalf(Bitcast(_uintType, Ext(37u, _floatType, a, b)));
                    return true;
                }
                case "VMinF16":
                {
                    var a = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 0), UInt(0xFFFF))));
                    var b = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 1), UInt(0xFFFF))));
                    result = EmitFloatToHalf(Bitcast(_uintType, Ext(38u, _floatType, a, b)));
                    return true;
                }
                case "VFmaF16":
                {
                    var a = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 0), UInt(0xFFFF))));
                    var b = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 1), UInt(0xFFFF))));
                    var c = Bitcast(_floatType, EmitHalfToFloat(
                        BitwiseAnd(GetRawSource(instruction, 2), UInt(0xFFFF))));
                    result = EmitFloatToHalf(Bitcast(_uintType, Ext(50u, _floatType, a, b, c)));
                    return true;
                }
                case "VPackB32F16":
                {
                    var lo = EmitFloatToHalf(Bitcast(_uintType, GetFloatSource(instruction, 0)));
                    var hi = EmitFloatToHalf(Bitcast(_uintType, GetFloatSource(instruction, 1)));
                    result = BitwiseOr(
                        BitwiseAnd(lo, UInt(0xFFFF)),
                        ShiftLeftLogical(BitwiseAnd(hi, UInt(0xFFFF)), UInt(16)));
                    return true;
                }
                case "VMadI32I24":
                {
                    var a = GetRawSource(instruction, 0);
                    var b = GetRawSource(instruction, 1);
                    var c = GetRawSource(instruction, 2);
                    var a24 = _module.AddInstruction(
                        SpirvOp.ShiftRightArithmetic,
                        _intType,
                        Bitcast(_intType, ShiftLeftLogical(a, UInt(8))),
                        UInt(8));
                    var b24 = _module.AddInstruction(
                        SpirvOp.ShiftRightArithmetic,
                        _intType,
                        Bitcast(_intType, ShiftLeftLogical(b, UInt(8))),
                        UInt(8));
                    var prod = _module.AddInstruction(SpirvOp.IMul, _intType, a24, b24);
                    result = Bitcast(
                        _uintType,
                        _module.AddInstruction(
                            SpirvOp.IAdd,
                            _intType,
                            prod,
                            Bitcast(_intType, c)));
                    return true;
                }
                case "VSubF64":
                case "VSubrevF64":
                {
                    var f64 = _module.TypeFloat(64);
                    var a = Bitcast(f64, GetRawSource64(instruction, 0));
                    var b = Bitcast(f64, GetRawSource64(instruction, 1));
                    if (instruction.Opcode == "VSubrevF64")
                    {
                        (a, b) = (b, a);
                    }

                    var bits = Bitcast(
                        _ulongType,
                        _module.AddInstruction(SpirvOp.FSub, f64, a, b));
                    var lo = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    var hi = _module.AddInstruction(
                        SpirvOp.UConvert,
                        _uintType,
                        ShiftRightLogical64(bits, _module.Constant64(_ulongType, 32)));
                    StoreV(destination, lo);
                    StoreV(destination + 1, hi);
                    result = lo;
                    return true;
                }
                case "VReadlaneB32":
                {
                    var value = GetRawSource(instruction, 0);
                    var laneMask = _waveLaneCount == 64 ? UInt(63) : UInt(31);
                    var laneSelect = BitwiseAnd(GetRawSource(instruction, 1), laneMask);
                    if (_subgroupInvocationIdInput != 0)
                    {
                        // ScopeSubgroup = 3
                        result = _module.AddInstruction(
                            SpirvOp.GroupNonUniformBroadcast,
                            _uintType,
                            UInt(3),
                            value,
                            laneSelect);
                    }
                    else
                    {
                        result = value;
                    }

                    return true;
                }
                default:
                    return false;
            }
        }
    }
}
