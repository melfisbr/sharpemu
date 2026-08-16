// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.Decoder;


public enum OperandType
{
    None,

    SGPR,

    VGPR,

    Constant,

    Literal,

    Immediate,

    SpecialRegister
}



public sealed class Operand
{
    public OperandType Type { get; init; }


    public int Index { get; init; }


    public uint Value { get; init; }


    public bool IsVector =>
        Type == OperandType.VGPR;


    public override string ToString()
    {
        return Type switch
        {
            OperandType.SGPR =>
                $"s{Index}",

            OperandType.VGPR =>
                $"v{Index}",

            OperandType.Constant =>
                $"c{Index}",

            OperandType.Immediate =>
                Value.ToString(),

            _ =>
                Type.ToString()
        };
    }
}