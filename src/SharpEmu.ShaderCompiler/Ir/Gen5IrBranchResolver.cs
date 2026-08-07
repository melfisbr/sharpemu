// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later


using System;


namespace SharpEmu.ShaderCompiler.IR;



public sealed class Gen5IrBranchResolver : IIrBranchResolver
{


    public static Gen5IrBranchResolver Instance { get; } = new();



    public bool IsBranch(
        Gen5ShaderInstruction instruction)
    {
        return IsUnconditionalBranch(instruction)
            || IsConditional(instruction)
            || IsTerminator(instruction);
    }



    public bool IsConditional(
        Gen5ShaderInstruction instruction)
    {

        return instruction.Opcode switch
        {

            "SCbranchScc0" or
            "SCbranchScc1" or
            "SCbranchVccz" or
            "SCbranchVccnz" or
            "SCbranchExecz" or
            "SCbranchExecnz"
                => true,


            _ => false
        };

    }




    public bool TryGetBranchTarget(
        Gen5ShaderInstruction instruction,
        out uint targetPc)
    {

        targetPc = 0;


        if(!IsBranch(instruction))
            return false;



        if(instruction.Words.Count == 0)
            return false;



        short offset =
            unchecked(
                (short)(instruction.Words[0] & 0xffff));



        long next =
            instruction.Pc +
            instruction.Words.Count *
            sizeof(uint);



        long target =
            next +
            offset *
            sizeof(uint);



        if(target < 0 ||
           target > uint.MaxValue)
            return false;



        targetPc =
            (uint)target;


        return true;

    }




    public bool Resolve(
        IRInstruction instruction)
    {

        return instruction.Opcode switch
        {

            IROpcode.Branch
                => true,


            IROpcode.BranchConditional
                => true,


            _ => false

        };

    }





    public static bool IsUnconditionalBranch(
        Gen5ShaderInstruction instruction)
    {

        return string.Equals(
            instruction.Opcode,
            "SBranch",
            StringComparison.Ordinal);

    }



    public static bool IsTerminator(
        Gen5ShaderInstruction instruction)
    {

        return instruction.Opcode is
            "SEndpgm" or
            "SEndpgmSaved";

    }

}