// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.Decoder;

public static class OperandDecoder
{
    private const int VectorRegisterBase = 128;
    private const int ImmediateBase = 224;
    private const int EncodedOperandLimit = 256;

    public static Operand DecodeVGPR(int index)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);

        return new Operand
        {
            Type = OperandType.VGPR,
            Index = index
        };
    }

    public static Operand DecodeSGPR(int index)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);

        return new Operand
        {
            Type = OperandType.SGPR,
            Index = index
        };
    }

    public static Operand DecodeImmediate(uint value)
    {
        return new Operand
        {
            Type = OperandType.Immediate,
            Value = value
        };
    }

    public static Operand DecodeRegister(int encoded)
    {
        ValidateEncodedOperand(encoded);

        return encoded >= VectorRegisterBase
            ? DecodeVGPR(encoded - VectorRegisterBase)
            : DecodeSGPR(encoded);
    }

    public static Operand Decode(int encoded)
    {
        ValidateEncodedOperand(encoded);

        if (encoded >= ImmediateBase)
        {
            return DecodeImmediate((uint)(encoded - ImmediateBase));
        }

        return DecodeRegister(encoded);
    }

    private static void ValidateEncodedOperand(int encoded)
    {
        if ((uint)encoded >= EncodedOperandLimit)
        {
            throw new ArgumentOutOfRangeException(
                nameof(encoded),
                encoded,
                "O operando codificado deve estar no intervalo de 0 a 255.");
        }
    }
}
