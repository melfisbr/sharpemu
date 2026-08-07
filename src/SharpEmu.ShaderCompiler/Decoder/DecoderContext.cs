// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.Decoder;



public sealed class DecoderContext
{

    public ReadOnlyMemory<byte> Code { get; }


    public ulong ProgramCounter { get; set; }



    public DecoderContext(
        ReadOnlyMemory<byte> code)
    {
        Code = code;
    }



    public uint ReadUInt32()
    {
        var span = Code.Span;

        int offset =
            checked((int)ProgramCounter);


        return BitConverter.ToUInt32(
            span.Slice(offset,4));
    }

}