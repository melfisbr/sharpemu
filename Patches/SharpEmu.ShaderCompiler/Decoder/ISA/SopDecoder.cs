// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.ShaderCompiler.Decoder;

namespace SharpEmu.ShaderCompiler.Decoder.ISA;


public static class SopDecoder
{
    public static Opcode Decode(uint opcode)
    {
        return opcode switch
        {
            0x00 => Opcode.S_ADD_U32,

            0x01 => Opcode.S_SUB_U32,

            _ => Opcode.Unknown
        };
    }


    public static void DecodeOperands(
        uint raw,
        DecodedInstruction result)
    {
        result.Operands.Add(
            OperandDecoder.DecodeRegister(
                (int)((raw >> 8) & 0xFF)));


        result.Operands.Add(
            OperandDecoder.Decode(
                (int)((raw >> 16) & 0xFF)));


        result.Operands.Add(
            OperandDecoder.Decode(
                (int)((raw >> 24) & 0xFF)));
    }
}