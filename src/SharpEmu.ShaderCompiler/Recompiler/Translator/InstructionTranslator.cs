// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.ShaderCompiler.Decoder;
using SharpEmu.ShaderCompiler.IR;

namespace SharpEmu.ShaderCompiler.Recompiler.Translator;

public sealed class InstructionTranslator
{
    private const int VectorRegisterBase = 256;
    private const int SpecialRegisterBase = 512;

    private readonly RecompilerContext _context;

    public InstructionTranslator(
        RecompilerContext context)
    {
        _context = context ??
            throw new ArgumentNullException(nameof(context));
    }

    public void Translate(
        DecodedInstruction instruction)
    {
        ArgumentNullException.ThrowIfNull(instruction);

        switch (instruction.Opcode)
        {
            case Opcode.V_ADD_F32:
                TranslateVectorBinary(
                    instruction,
                    IROpcode.Add);
                break;

            case Opcode.V_MUL_F32:
                TranslateVectorBinary(
                    instruction,
                    IROpcode.Mul);
                break;

            default:
                throw new NotSupportedException(
                    $"Opcode {instruction.Opcode} not implemented");
        }
    }

    private void TranslateVectorBinary(
        DecodedInstruction instruction,
        IROpcode opcode)
    {
        if (instruction.Operands.Count < 3)
        {
            throw new InvalidOperationException(
                $"{instruction.Opcode} requires one destination and two source operands.");
        }

        var destination = instruction.Operands[0];
        if (destination.Type != OperandType.VGPR)
        {
            throw new InvalidOperationException(
                $"{instruction.Opcode} requires a VGPR destination.");
        }

        var left = ResolveSource(
            instruction.Operands[1],
            IRType.Float32);

        var right = ResolveSource(
            instruction.Operands[2],
            IRType.Float32);

        var result = _context.Builder.CreateValue(
            IRType.Float32,
            $"v{destination.Index}");

        var irInstruction = _context.Builder.CreateInstruction(
            opcode,
            result);

        irInstruction.AddOperand(left);
        irInstruction.AddOperand(right);

        _context.Builder.Module.AddInstruction(
            irInstruction);

        _context.Registers[GetRegisterKey(destination)] =
            result;
    }

    private IRValue ResolveSource(
        Operand operand,
        IRType preferredType)
    {
        if (IsRegister(operand))
        {
            var key = GetRegisterKey(operand);

            if (_context.Registers.TryGetValue(
                    key,
                    out var existing))
            {
                return existing;
            }

            var register = _context.Builder.CreateValue(
                preferredType,
                GetOperandName(operand));

            _context.Registers.Add(
                key,
                register);

            return register;
        }

        return _context.Builder.CreateValue(
            preferredType,
            GetOperandName(operand));
    }

    private static bool IsRegister(
        Operand operand) =>
        operand.Type is
            OperandType.SGPR or
            OperandType.VGPR or
            OperandType.SpecialRegister;

    private static int GetRegisterKey(
        Operand operand)
    {
        return operand.Type switch
        {
            OperandType.SGPR => operand.Index,
            OperandType.VGPR => checked(
                VectorRegisterBase + operand.Index),
            OperandType.SpecialRegister => checked(
                SpecialRegisterBase + operand.Index),

            _ => throw new ArgumentException(
                "The operand is not a register.",
                nameof(operand))
        };
    }

    private static string GetOperandName(
        Operand operand)
    {
        return operand.Type switch
        {
            OperandType.SGPR => $"s{operand.Index}",
            OperandType.VGPR => $"v{operand.Index}",
            OperandType.Constant => $"c{operand.Index}",
            OperandType.Literal => $"literal_{operand.Value:X8}",
            OperandType.Immediate => $"imm_{operand.Value}",
            OperandType.SpecialRegister => $"special_{operand.Index}",
            _ => "operand"
        };
    }
}
