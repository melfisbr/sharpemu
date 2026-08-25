// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later


namespace SharpEmu.ShaderCompiler.Decoder;


public sealed class DecodedInstruction
{

    public ulong Address { get; init; }


    public uint RawOpcode { get; init; }


    public Opcode Opcode { get; init; }


    public InstructionFormat Format { get; init; }


    public Operand? Destination { get; init; }


    public IReadOnlyList<Operand> Sources { get; init; }
        = Array.Empty<Operand>();


    public List<Operand> Operands { get; init; }
        = new();


    public int Size { get; init; }



    public override string ToString()
    {
        if (Operands.Count == 0)
            return $"{Address:X8}: {Opcode}";


        return
            $"{Address:X8}: {Opcode} ({string.Join(", ", Operands)})";
    }
}