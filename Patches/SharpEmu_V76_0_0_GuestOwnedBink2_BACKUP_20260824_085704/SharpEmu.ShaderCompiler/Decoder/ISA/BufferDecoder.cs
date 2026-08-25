// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later


using SharpEmu.ShaderCompiler.Decoder;


namespace SharpEmu.ShaderCompiler.Decoder.ISA;


public enum BufferOpcode
{
    Load,
    Store,
    Atomic,
    Unknown
}



public static class BufferDecoder
{


    public static BufferOpcode Decode(
        uint raw)
    {

        return (raw & 0xFF) switch
        {
            0x40 => BufferOpcode.Load,
            0x41 => BufferOpcode.Store,
            0x42 => BufferOpcode.Atomic,

            _ => BufferOpcode.Unknown
        };

    }



    public static void DecodeOperands(
        uint raw,
        DecodedInstruction result)
    {

        int buffer =
            (int)((raw >> 8) & 0xFF);



        result.Operands.Add(
            OperandDecoder.DecodeRegister(buffer));
    }
}