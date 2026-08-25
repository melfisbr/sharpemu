// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.Decoder;

public enum Opcode
{
    Unknown = 0,

    // Scalar (SOP)
    S_MOV_B32,
    S_ADD_U32,
    S_SUB_U32,
    S_BRANCH,
    S_ENDPGM,

    // Vector (VOP)
    V_MOV_B32,
    V_ADD_F32,
    V_SUB_F32,
    V_MUL_F32,
    V_MIN_F32,
    V_MAX_F32,

    // Scalar Memory (SMEM)
    S_LOAD_DWORD,
    S_STORE_DWORD,

    // Buffer
    BUFFER_LOAD,
    BUFFER_STORE,

    // Image
    IMAGE_LOAD,
    IMAGE_STORE,
    IMAGE_SAMPLE,
    IMAGE_GATHER
}

public sealed class OpcodeInfo
{
    public Opcode Opcode { get; init; }

    public InstructionFormat Format { get; init; }

    public string Name { get; init; } = string.Empty;
}

public static class OpcodeTable
{
    private static readonly Dictionary<int, OpcodeInfo> _table = new()
    {
        // ==========================
        // SOP
        // ==========================

        [0x00] = new()
        {
            Opcode = Opcode.S_MOV_B32,
            Format = InstructionFormat.SOP2,
            Name = "s_mov_b32"
        },

        [0x01] = new()
        {
            Opcode = Opcode.S_ADD_U32,
            Format = InstructionFormat.SOP2,
            Name = "s_add_u32"
        },

        [0x02] = new()
        {
            Opcode = Opcode.S_SUB_U32,
            Format = InstructionFormat.SOP2,
            Name = "s_sub_u32"
        },

        [0x03] = new()
        {
            Opcode = Opcode.S_BRANCH,
            Format = InstructionFormat.SOPP,
            Name = "s_branch"
        },

        [0x04] = new()
        {
            Opcode = Opcode.S_ENDPGM,
            Format = InstructionFormat.SOPP,
            Name = "s_endpgm"
        },

        // ==========================
        // VOP
        // ==========================

        [0x20] = new()
        {
            Opcode = Opcode.V_MOV_B32,
            Format = InstructionFormat.VOP1,
            Name = "v_mov_b32"
        },

        [0x21] = new()
        {
            Opcode = Opcode.V_ADD_F32,
            Format = InstructionFormat.VOP2,
            Name = "v_add_f32"
        },

        [0x22] = new()
        {
            Opcode = Opcode.V_SUB_F32,
            Format = InstructionFormat.VOP2,
            Name = "v_sub_f32"
        },

        [0x23] = new()
        {
            Opcode = Opcode.V_MUL_F32,
            Format = InstructionFormat.VOP2,
            Name = "v_mul_f32"
        },

        [0x24] = new()
        {
            Opcode = Opcode.V_MIN_F32,
            Format = InstructionFormat.VOP2,
            Name = "v_min_f32"
        },

        [0x25] = new()
        {
            Opcode = Opcode.V_MAX_F32,
            Format = InstructionFormat.VOP2,
            Name = "v_max_f32"
        },

        // ==========================
        // SMEM
        // ==========================

        [0x40] = new()
        {
            Opcode = Opcode.S_LOAD_DWORD,
            Format = InstructionFormat.SMEM,
            Name = "s_load_dword"
        },

        [0x41] = new()
        {
            Opcode = Opcode.S_STORE_DWORD,
            Format = InstructionFormat.SMEM,
            Name = "s_store_dword"
        },

        // ==========================
        // BUFFER
        // ==========================

        [0x60] = new()
        {
            Opcode = Opcode.BUFFER_LOAD,
            Format = InstructionFormat.BUFFER,
            Name = "buffer_load"
        },

        [0x61] = new()
        {
            Opcode = Opcode.BUFFER_STORE,
            Format = InstructionFormat.BUFFER,
            Name = "buffer_store"
        },

        // ==========================
        // IMAGE
        // ==========================

        [0x80] = new()
        {
            Opcode = Opcode.IMAGE_LOAD,
            Format = InstructionFormat.IMAGE,
            Name = "image_load"
        },

        [0x81] = new()
        {
            Opcode = Opcode.IMAGE_STORE,
            Format = InstructionFormat.IMAGE,
            Name = "image_store"
        },

        [0x82] = new()
        {
            Opcode = Opcode.IMAGE_SAMPLE,
            Format = InstructionFormat.IMAGE,
            Name = "image_sample"
        },

        [0x83] = new()
        {
            Opcode = Opcode.IMAGE_GATHER,
            Format = InstructionFormat.IMAGE,
            Name = "image_gather"
        }
    };

    public static bool TryGet(
        int opcode,
        out OpcodeInfo info)
    {
        return _table.TryGetValue(opcode, out info!);
    }
}