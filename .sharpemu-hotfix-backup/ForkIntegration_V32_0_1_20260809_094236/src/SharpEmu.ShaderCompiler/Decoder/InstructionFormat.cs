// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.Decoder;

public enum InstructionFormat
{
    Unknown,

    SOP,
    SOP1,
    SOP2,
    SOPK,
    SOPP,

    VOP,
    VOP1,
    VOP2,
    VOP3,
    VOPC,

    SMEM,
    DS,
    BUFFER,
    IMAGE
}
