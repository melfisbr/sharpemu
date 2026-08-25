// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.ShaderCompiler.Decoder.ISA;

namespace SharpEmu.ShaderCompiler.Decoder;

public sealed class InstructionDecoder
{
    public DecodedInstruction Decode(
        DecoderContext context)
    {
        ulong address = context.ProgramCounter;

        uint raw = context.ReadUInt32();


        int opcodeValue =
            (int)(raw & 0xFF);


        if (!OpcodeTable.TryGet(
            opcodeValue,
            out var info))
        {
            return new DecodedInstruction
            {
                Address = address,
                RawOpcode = raw,
                Opcode = Opcode.Unknown,
                Format = InstructionFormat.Unknown,
                Size = 4,
                Operands = new List<Operand>()
            };
        }


        var instruction = new DecodedInstruction
        {
            Address = address,
            RawOpcode = raw,
            Opcode = info.Opcode,
            Format = info.Format,
            Size = 4,
            Operands = new List<Operand>()
        };


        switch(info.Format)
        {
            case InstructionFormat.SOP:
            case InstructionFormat.SOP2:
            case InstructionFormat.SOPK:
            case InstructionFormat.SOPP:

                SopDecoder.DecodeOperands(
                    raw,
                    instruction);

                break;


            case InstructionFormat.VOP:
            case InstructionFormat.VOP2:
            case InstructionFormat.VOP3:

                VopDecoder.DecodeOperands(
                    raw,
                    instruction);

                break;


            case InstructionFormat.SMEM:

                SmemDecoder.DecodeOperands(
                    raw,
                    instruction);

                break;


            case InstructionFormat.IMAGE:

                ImageDecoder.DecodeOperands(
                    raw,
                    instruction);

                break;


            case InstructionFormat.BUFFER:

                BufferDecoder.DecodeOperands(
                    raw,
                    instruction);

                break;
        }


        return instruction;
    }
}