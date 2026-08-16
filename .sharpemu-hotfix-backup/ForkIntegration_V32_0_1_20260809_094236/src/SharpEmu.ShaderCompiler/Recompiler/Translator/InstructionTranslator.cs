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
            case Opcode.V_MOV_B32:
                TranslateMove(instruction, IRType.UInt32);
                break;

            case Opcode.S_MOV_B32:
                TranslateMove(instruction, IRType.UInt32);
                break;

            case Opcode.V_ADD_F32:
                TranslateBinary(instruction, IROpcode.Add, IRType.Float32);
                break;

            case Opcode.V_SUB_F32:
                TranslateBinary(instruction, IROpcode.Sub, IRType.Float32);
                break;

            case Opcode.V_MUL_F32:
                TranslateBinary(instruction, IROpcode.Mul, IRType.Float32);
                break;

            case Opcode.V_MIN_F32:
                TranslateBinary(instruction, IROpcode.Min, IRType.Float32);
                break;

            case Opcode.V_MAX_F32:
                TranslateBinary(instruction, IROpcode.Max, IRType.Float32);
                break;

            case Opcode.S_ADD_U32:
                TranslateBinary(instruction, IROpcode.Add, IRType.UInt32);
                break;

            case Opcode.S_SUB_U32:
                TranslateBinary(instruction, IROpcode.Sub, IRType.UInt32);
                break;

            default:
                throw new NotSupportedException(
                    $"Opcode {instruction.Opcode} not implemented by the generic IR recompiler.");
        }
    }

    private void TranslateMove(
        DecodedInstruction instruction,
        IRType valueType)
    {
        if (instruction.Operands.Count < 2)
        {
            throw new InvalidOperationException(
                $"{instruction.Opcode} requires one destination and one source operand.");
        }

        var destination = instruction.Operands[0];
        if (!IsRegister(destination))
        {
            throw new InvalidOperationException(
                $"{instruction.Opcode} requires a register destination.");
        }

        var source = ResolveSource(instruction.Operands[1], valueType);
        _context.Registers[GetRegisterKey(destination)] = source;
    }

    private void TranslateBinary(
        DecodedInstruction instruction,
        IROpcode opcode,
        IRType valueType)
    {
        if (instruction.Operands.Count < 3)
        {
            throw new InvalidOperationException(
                $"{instruction.Opcode} requires one destination and two source operands.");
        }

        var destination = instruction.Operands[0];
        if (!IsRegister(destination))
        {
            throw new InvalidOperationException(
                $"{instruction.Opcode} requires a register destination.");
        }

        var left = ResolveSource(
            instruction.Operands[1],
            valueType);

        var right = ResolveSource(
            instruction.Operands[2],
            valueType);

        var result = _context.Builder.CreateValue(
            valueType,
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
