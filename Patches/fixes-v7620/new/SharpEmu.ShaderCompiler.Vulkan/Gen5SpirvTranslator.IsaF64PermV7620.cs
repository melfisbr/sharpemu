// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.0: F64 arithmetic/converts, V_PERM_B32, V_DOT4_I32_I8, 64-bit VGPR shifts.

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private uint DoubleTypeV7620() => _module.TypeFloat(64);

        private uint AsDoubleV7620(uint ulongBits) =>
            Bitcast(DoubleTypeV7620(), ulongBits);

        private uint AsUlongBitsV7620(uint doubleValue) =>
            Bitcast(_ulongType, doubleValue);

        private void StoreVgprPairV7620(uint destination, uint ulongValue)
        {
            var lo = _module.AddInstruction(SpirvOp.UConvert, _uintType, ulongValue);
            var hi = _module.AddInstruction(
                SpirvOp.UConvert,
                _uintType,
                ShiftRightLogical64(ulongValue, _module.Constant64(_ulongType, 32)));
            StoreV(destination, lo);
            StoreV(destination + 1, hi);
        }

        private bool TryEmitExtraVectorOpcodeV7620(
            Gen5ShaderInstruction instruction,
            uint destination,
            out uint result,
            out string error)
        {
            result = 0;
            error = string.Empty;
            var f64 = DoubleTypeV7620();

            switch (instruction.Opcode)
            {
                case "VAddF64":
                {
                    var sum = _module.AddInstruction(
                        SpirvOp.FAdd,
                        f64,
                        AsDoubleV7620(GetRawSource64(instruction, 0)),
                        AsDoubleV7620(GetRawSource64(instruction, 1)));
                    var bits = AsUlongBitsV7620(sum);
                    StoreVgprPairV7620(destination, bits);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    return true;
                }
                case "VMulF64":
                {
                    var prod = _module.AddInstruction(
                        SpirvOp.FMul,
                        f64,
                        AsDoubleV7620(GetRawSource64(instruction, 0)),
                        AsDoubleV7620(GetRawSource64(instruction, 1)));
                    var bits = AsUlongBitsV7620(prod);
                    StoreVgprPairV7620(destination, bits);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    return true;
                }
                case "VFmaF64":
                {
                    var fma = Ext(
                        50u,
                        f64,
                        AsDoubleV7620(GetRawSource64(instruction, 0)),
                        AsDoubleV7620(GetRawSource64(instruction, 1)),
                        AsDoubleV7620(GetRawSource64(instruction, 2)));
                    var bits = AsUlongBitsV7620(fma);
                    StoreVgprPairV7620(destination, bits);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    return true;
                }
                case "VRcpF64":
                {
                    var oneD = AsDoubleV7620(_module.Constant64(_ulongType, 0x3FF0000000000000UL));
                    var rcp = _module.AddInstruction(
                        SpirvOp.FDiv,
                        f64,
                        oneD,
                        AsDoubleV7620(GetRawSource64(instruction, 0)));
                    var bits = AsUlongBitsV7620(rcp);
                    StoreVgprPairV7620(destination, bits);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    return true;
                }
                case "VSqrtF64":
                {
                    var s = Ext(31u, f64, AsDoubleV7620(GetRawSource64(instruction, 0)));
                    var bits = AsUlongBitsV7620(s);
                    StoreVgprPairV7620(destination, bits);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    return true;
                }
                case "VCvtF32F64":
                {
                    var f = _module.AddInstruction(
                        SpirvOp.FConvert,
                        _floatType,
                        AsDoubleV7620(GetRawSource64(instruction, 0)));
                    result = Bitcast(_uintType, f);
                    return true;
                }
                case "VCvtF64F32":
                {
                    var d = _module.AddInstruction(
                        SpirvOp.FConvert,
                        f64,
                        GetFloatSource(instruction, 0));
                    var bits = AsUlongBitsV7620(d);
                    StoreVgprPairV7620(destination, bits);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    return true;
                }
                case "VPermB32":
                {
                    var src0 = GetRawSource(instruction, 0);
                    var src1 = GetRawSource(instruction, 1);
                    var sel = GetRawSource(instruction, 2);
                    var data = BitwiseOr64(
                        _module.AddInstruction(SpirvOp.UConvert, _ulongType, src0),
                        ShiftLeftLogical64(
                            _module.AddInstruction(SpirvOp.UConvert, _ulongType, src1),
                            _module.Constant64(_ulongType, 32)));

                    uint BytePick(uint nibbleIndex)
                    {
                        var shiftSel = ShiftRightLogical(sel, UInt(nibbleIndex * 4));
                        var byteIndex = BitwiseAnd(shiftSel, UInt(7));
                        var bitShift = _module.AddInstruction(
                            SpirvOp.IMul,
                            _uintType,
                            byteIndex,
                            UInt(8));
                        var shifted = ShiftRightLogical64(
                            data,
                            _module.AddInstruction(SpirvOp.UConvert, _ulongType, bitShift));
                        return BitwiseAnd(
                            _module.AddInstruction(SpirvOp.UConvert, _uintType, shifted),
                            UInt(0xFF));
                    }

                    result = BitwiseOr(
                        BitwiseOr(BytePick(0), ShiftLeftLogical(BytePick(1), UInt(8))),
                        BitwiseOr(
                            ShiftLeftLogical(BytePick(2), UInt(16)),
                            ShiftLeftLogical(BytePick(3), UInt(24))));
                    return true;
                }
                case "VDot4I32I8":
                {
                    var a = GetRawSource(instruction, 0);
                    var b = GetRawSource(instruction, 1);
                    var sum = _module.Constant(_intType, 0);
                    for (var i = 0; i < 4; i++)
                    {
                        var sh = UInt((uint)(i * 8));
                        uint Sx(uint v)
                        {
                            var raw = BitwiseAnd(ShiftRightLogical(v, sh), UInt(0xFF));
                            var neg = IsNotZero(BitwiseAnd(raw, UInt(0x80)));
                            var ext = _module.AddInstruction(
                                SpirvOp.Select,
                                _uintType,
                                neg,
                                BitwiseOr(raw, UInt(0xFFFFFF00u)),
                                raw);
                            return Bitcast(_intType, ext);
                        }

                        var prod = _module.AddInstruction(
                            SpirvOp.IMul,
                            _intType,
                            Sx(a),
                            Sx(b));
                        sum = _module.AddInstruction(SpirvOp.IAdd, _intType, sum, prod);
                    }

                    if (instruction.Sources.Count > 2)
                    {
                        sum = _module.AddInstruction(
                            SpirvOp.IAdd,
                            _intType,
                            sum,
                            Bitcast(_intType, GetRawSource(instruction, 2)));
                    }

                    result = Bitcast(_uintType, sum);
                    return true;
                }
                case "VLShlrevB64":
                case "VLshlrevB64":
                {
                    var shift = BitwiseAnd(GetRawSource(instruction, 0), UInt(63));
                    var shifted = ShiftLeftLogical64(
                        GetRawSource64(instruction, 1),
                        _module.AddInstruction(SpirvOp.UConvert, _ulongType, shift));
                    StoreVgprPairV7620(destination, shifted);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, shifted);
                    return true;
                }
                case "VLShrrevB64":
                case "VLshrrevB64":
                {
                    var shift = BitwiseAnd(GetRawSource(instruction, 0), UInt(63));
                    var shifted = ShiftRightLogical64(
                        GetRawSource64(instruction, 1),
                        _module.AddInstruction(SpirvOp.UConvert, _ulongType, shift));
                    StoreVgprPairV7620(destination, shifted);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, shifted);
                    return true;
                }
                case "VAshrrevI64":
                {
                    var shift = BitwiseAnd(GetRawSource(instruction, 0), UInt(63));
                    var signedTy = _module.TypeInt(64, signed: true);
                    var value = Bitcast(signedTy, GetRawSource64(instruction, 1));
                    var shifted = _module.AddInstruction(
                        SpirvOp.ShiftRightArithmetic,
                        signedTy,
                        value,
                        _module.AddInstruction(SpirvOp.UConvert, _ulongType, shift));
                    var bits = Bitcast(_ulongType, shifted);
                    StoreVgprPairV7620(destination, bits);
                    result = _module.AddInstruction(SpirvOp.UConvert, _uintType, bits);
                    return true;
                }
                default:
                    return false;
            }
        }
    }
}
