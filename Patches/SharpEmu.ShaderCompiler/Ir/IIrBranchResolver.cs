// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later


namespace SharpEmu.ShaderCompiler.IR;


public interface IIrBranchResolver
{

    bool IsBranch(
        Gen5ShaderInstruction instruction);



    bool IsConditional(
        Gen5ShaderInstruction instruction);



    bool TryGetBranchTarget(
        Gen5ShaderInstruction instruction,
        out uint targetPc);



    bool Resolve(
        IRInstruction instruction);

}