// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.IR;

/// <summary>
/// Represents one immutable IR operation. Operands remain append-only while
/// the instruction is being built through <see cref="IRBuilder"/>.
/// </summary>
public sealed class IRInstruction
{
    public IROpcode Opcode { get; }

    public List<IRValue> Operands { get; }

    public IRValue? Result { get; }

    public IRType Type { get; }

    public IRInstruction(IROpcode opcode)
        : this(opcode, IRType.Void)
    {
    }

    public IRInstruction(IROpcode opcode, IRValue result)
        : this(
            opcode,
            result?.Type ?? throw new ArgumentNullException(nameof(result)),
            result)
    {
    }

    public IRInstruction(
        IROpcode opcode,
        IRType type,
        IRValue? result = null)
    {
        Opcode = opcode;
        Type = type;
        Result = result;
        Operands = new List<IRValue>();
    }

    public IRInstruction AddOperand(IRValue value)
    {
        ArgumentNullException.ThrowIfNull(value);
        Operands.Add(value);
        return this;
    }

    public IRInstruction AddOperands(IEnumerable<IRValue> values)
    {
        ArgumentNullException.ThrowIfNull(values);

        foreach (var value in values)
        {
            AddOperand(value);
        }

        return this;
    }
}
