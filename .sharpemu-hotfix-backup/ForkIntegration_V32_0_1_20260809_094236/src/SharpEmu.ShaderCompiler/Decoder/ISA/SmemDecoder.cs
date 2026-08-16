// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later


using SharpEmu.ShaderCompiler.Decoder;


namespace SharpEmu.ShaderCompiler.Decoder.ISA;


public enum SmemOpcode
{
    Load,
    Store,
    Atomic,
    Unknown
}



public static class SmemDecoder
{

    public static SmemOpcode Decode(
        uint raw)
    {

        return (raw & 0xFF) switch
        {
            0x20 => SmemOpcode.Load,
            0x21 => SmemOpcode.Store,
            0x22 => SmemOpcode.Atomic,

            _ => SmemOpcode.Unknown
        };
    }



    public static void DecodeOperands(
        uint raw,
        DecodedInstruction result)
    {

        int address =
            (int)((raw >> 8) & 0xFF);



        result.Operands.Add(
            OperandDecoder.DecodeRegister(address));
    }
}