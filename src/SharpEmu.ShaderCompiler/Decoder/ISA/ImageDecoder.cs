// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later


using SharpEmu.ShaderCompiler.Decoder;


namespace SharpEmu.ShaderCompiler.Decoder.ISA;


public enum ImageOpcode
{
    Load,
    Store,
    Sample,
    Gather,
    Atomic,
    Unknown
}



public static class ImageDecoder
{


    public static ImageOpcode Decode(
        uint raw)
    {

        return (raw & 0xFF) switch
        {
            0x30 => ImageOpcode.Load,
            0x31 => ImageOpcode.Store,
            0x32 => ImageOpcode.Sample,
            0x33 => ImageOpcode.Gather,
            0x34 => ImageOpcode.Atomic,

            _ => ImageOpcode.Unknown
        };

    }



    public static void DecodeOperands(
        uint raw,
        DecodedInstruction result)
    {

        int imageRegister =
            (int)((raw >> 8) & 0xFF);



        result.Operands.Add(
            OperandDecoder.DecodeRegister(
                imageRegister));
    }
}