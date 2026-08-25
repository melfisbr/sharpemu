// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.ShaderCompiler.Decoder;
using SharpEmu.ShaderCompiler.IR;

namespace SharpEmu.ShaderCompiler.Translator;

/// <summary>
/// Converts decoded PS5 GCN/RDNA instructions into SharpEmu IR.
/// </summary>
public static class IsaToIrTranslator
{
    public static IRModule Translate(
        IReadOnlyList<DecodedInstruction> instructions)
    {
        ArgumentNullException.ThrowIfNull(instructions);

        var module = new IRModule();
        var nextValueId = 1;

        foreach (var instruction in instructions)
        {
            module.AddInstruction(
                TranslateInstruction(
                    instruction,
                    ref nextValueId));
        }

        return module;
    }

    private static IRInstruction TranslateInstruction(
        DecodedInstruction instruction,
        ref int nextValueId)
    {
        ArgumentNullException.ThrowIfNull(instruction);

        var opcode = TranslateOpcode(instruction.Opcode);
        var type = GetResultType(instruction);

        var irInstruction = new IRInstruction(
            opcode,
            type);

        irInstruction.AddOperands(
            ConvertOperands(
                instruction,
                type,
                ref nextValueId));

        return irInstruction;
    }

    private static IRType GetResultType(
        DecodedInstruction instruction)
    {
        return instruction.Format switch
        {
            InstructionFormat.VOP or
            InstructionFormat.VOP1 or
            InstructionFormat.VOP2 or
            InstructionFormat.VOP3 or
            InstructionFormat.VOPC => IRType.Float32,

            InstructionFormat.IMAGE => IRType.Vector4,

            InstructionFormat.SMEM or
            InstructionFormat.BUFFER or
            InstructionFormat.DS => IRType.UInt32,

            InstructionFormat.SOP or
            InstructionFormat.SOP1 or
            InstructionFormat.SOP2 or
            InstructionFormat.SOPK => IRType.Int32,

            InstructionFormat.SOPP => IRType.Void,

            _ => IRType.Void
        };
    }

    private static IROpcode TranslateOpcode(
        Opcode opcode)
    {
        return opcode switch
        {
            Opcode.S_MOV_B32 or
            Opcode.V_MOV_B32 => IROpcode.Nop,

            Opcode.S_ADD_U32 or
            Opcode.V_ADD_F32 => IROpcode.Add,

            Opcode.S_SUB_U32 or
            Opcode.V_SUB_F32 => IROpcode.Sub,

            Opcode.V_MUL_F32 => IROpcode.Mul,

            Opcode.V_MIN_F32 => IROpcode.Min,
            Opcode.V_MAX_F32 => IROpcode.Max,

            Opcode.S_LOAD_DWORD or
            Opcode.BUFFER_LOAD or
            Opcode.IMAGE_LOAD => IROpcode.Load,

            Opcode.S_STORE_DWORD or
            Opcode.BUFFER_STORE or
            Opcode.IMAGE_STORE => IROpcode.Store,

            Opcode.IMAGE_SAMPLE or
            Opcode.IMAGE_GATHER => IROpcode.SampleTexture,

            Opcode.S_BRANCH => IROpcode.Branch,
            Opcode.S_ENDPGM => IROpcode.Return,

            _ => IROpcode.Nop
        };
    }

    private static List<IRValue> ConvertOperands(
        DecodedInstruction instruction,
        IRType instructionType,
        ref int nextValueId)
    {
        var values = new List<IRValue>(
            instruction.Operands.Count);

        foreach (var operand in instruction.Operands)
        {
            var type = GetOperandType(
                operand,
                instructionType);

            var name = operand.Type switch
            {
                OperandType.SGPR => $"s{operand.Index}",
                OperandType.VGPR => $"v{operand.Index}",
                OperandType.Constant => $"c{operand.Index}",
                OperandType.Literal => $"literal_{operand.Value:X8}",
                OperandType.Immediate => $"imm_{operand.Value}",
                OperandType.SpecialRegister => $"special_{operand.Index}",
                _ => $"operand_{nextValueId}"
            };

            values.Add(
                new IRValue(
                    nextValueId++,
                    type,
                    name));
        }

        return values;
    }

    private static IRType GetOperandType(
        Operand operand,
        IRType instructionType)
    {
        return operand.Type switch
        {
            OperandType.VGPR when instructionType is
                IRType.Float32 or
                IRType.Vector2 or
                IRType.Vector3 or
                IRType.Vector4 => instructionType,

            OperandType.Immediate or
            OperandType.Literal or
            OperandType.Constant => IRType.UInt32,

            OperandType.SGPR or
            OperandType.VGPR or
            OperandType.SpecialRegister => IRType.UInt32,

            _ => IRType.UInt32
        };
    }
}
