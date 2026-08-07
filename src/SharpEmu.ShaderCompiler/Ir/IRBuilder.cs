// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.IR;


public sealed class IRBuilder
{
    private int _nextValueId = 1;


    public IRModule Module { get; }


    public IRBuilder()
    {
        Module = new IRModule();
    }


    public IRValue CreateValue(
        IRType type,
        string? name = null)
    {
        var value = new IRValue(
            _nextValueId++,
            type,
            name);

        return value;
    }


    public IRInstruction CreateInstruction(
        IROpcode opcode)
    {
        return new IRInstruction(
            opcode);
    }


    public IRInstruction CreateInstruction(
        IROpcode opcode,
        IRValue result)
    {
        return new IRInstruction(
            opcode,
            result);
    }


    public IRInstruction Emit(
        IROpcode opcode,
        params IRValue[] operands)
    {
        var instruction =
            new IRInstruction(
                opcode);


        foreach(var operand in operands)
        {
            instruction.AddOperand(
                operand);
        }


        Module.AddInstruction(
            instruction);


        return instruction;
    }
}