// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        // V76.0.8: inverse of EmitBufferFormatLoad. RDNA2 format stores do not
        // write raw VGPR dwords: the texture unit converts source components to
        // the selected buffer format before memory is updated. MTBUF carries
        // FORMAT in the instruction and uses identity channel selection. MUBUF
        // takes FORMAT and dst_sel from the resource descriptor.
        private void EmitBufferFormatStoreV7608(
            int bindingIndex,
            uint byteAddress,
            uint scalarResource,
            Gen5BufferMemoryControl control)
        {
            var descriptorWord3 = LoadS(scalarResource + 3);
            var typed = control.TypedFormat.HasValue;
            var unifiedFormat = typed
                ? UInt(control.TypedFormat.GetValueOrDefault())
                : BitwiseAnd(
                    ShiftRightLogical(descriptorWord3, UInt(12)),
                    UInt(0x7F));
            var (dataFormat, numberFormat) = DecodeGfx10BufferFormat(unifiedFormat);

            for (var sourceComponent = 0;
                 sourceComponent < checked((int)control.ComponentCount);
                 sourceComponent++)
            {
                var source = LoadGfx10BufferFormatStoreSourceV7608(
                    control,
                    numberFormat,
                    sourceComponent);

                if (typed)
                {
                    StoreGfx10BufferFormatComponentV7608(
                        bindingIndex,
                        byteAddress,
                        dataFormat,
                        numberFormat,
                        sourceComponent,
                        source);
                    continue;
                }

                // BUFFER_STORE_FORMAT uses the SRD dst_sel. Interpret each
                // logical VDATA component as targeting the resource channel
                // named by its selector (X/Y/Z/W = 4/5/6/7). ZERO/ONE do not
                // name a memory component and therefore consume no store data.
                var selector = BitwiseAnd(
                    ShiftRightLogical(
                        descriptorWord3,
                        UInt((uint)sourceComponent * 3)),
                    UInt(7));
                for (var memoryComponent = 0; memoryComponent < 4; memoryComponent++)
                {
                    var targetsComponent = _module.AddInstruction(
                        SpirvOp.IEqual,
                        _boolType,
                        selector,
                        UInt((uint)(4 + memoryComponent)));
                    var capturedComponent = memoryComponent;
                    EmitConditional(
                        targetsComponent,
                        () => StoreGfx10BufferFormatComponentV7608(
                            bindingIndex,
                            byteAddress,
                            dataFormat,
                            numberFormat,
                            capturedComponent,
                            source));
                }
            }
        }

        private uint LoadGfx10BufferFormatStoreSourceV7608(
            Gen5BufferMemoryControl control,
            uint numberFormat,
            int component)
        {
            if (!control.D16)
            {
                return LoadV(control.VectorData + (uint)component);
            }

            // D16 stores pack X/Y and Z/W in low/high 16-bit halves. Integer
            // formats consume integer halves; all other buffer number formats
            // consume IEEE f16 and are widened to canonical f32 before the
            // ordinary format conversion below.
            var packed = LoadV(control.VectorData + (uint)(component / 2));
            var half = component % 2 == 0
                ? BitwiseAnd(packed, UInt(0xFFFF))
                : BitwiseAnd(ShiftRightLogical(packed, UInt(16)), UInt(0xFFFF));
            var isUint = _module.AddInstruction(
                SpirvOp.IEqual,
                _boolType,
                numberFormat,
                UInt(4));
            var isSint = _module.AddInstruction(
                SpirvOp.IEqual,
                _boolType,
                numberFormat,
                UInt(5));
            var isInteger = _module.AddInstruction(
                SpirvOp.LogicalOr,
                _boolType,
                isUint,
                isSint);
            var signedHalf = Bitcast(
                _uintType,
                _module.AddInstruction(
                    SpirvOp.BitFieldSExtract,
                    _intType,
                    Bitcast(_intType, half),
                    UInt(0),
                    UInt(16)));
            var integerValue = _module.AddInstruction(
                SpirvOp.Select,
                _uintType,
                isSint,
                signedHalf,
                half);
            return _module.AddInstruction(
                SpirvOp.Select,
                _uintType,
                isInteger,
                integerValue,
                EmitHalfToFloat(half));
        }

        private void StoreGfx10BufferFormatComponentV7608(
            int bindingIndex,
            uint elementAddress,
            uint dataFormat,
            uint numberFormat,
            int component,
            uint canonical)
        {
            var byteOffset = UInt(0);
            var bitOffset = UInt(0);
            var bitCount = UInt(0);

            void SetLayout(uint format, uint bytes, uint bits, uint count)
            {
                var matches = _module.AddInstruction(
                    SpirvOp.IEqual,
                    _boolType,
                    dataFormat,
                    UInt(format));
                byteOffset = _module.AddInstruction(
                    SpirvOp.Select,
                    _uintType,
                    matches,
                    UInt(bytes),
                    byteOffset);
                bitOffset = _module.AddInstruction(
                    SpirvOp.Select,
                    _uintType,
                    matches,
                    UInt(bits),
                    bitOffset);
                bitCount = _module.AddInstruction(
                    SpirvOp.Select,
                    _uintType,
                    matches,
                    UInt(count),
                    bitCount);
            }

            // Keep this layout byte-for-byte equivalent to the load-side
            // GFX10 legacy DATA_FORMAT mapping.
            switch (component)
            {
                case 0:
                    SetLayout(1, 0, 0, 8);
                    SetLayout(2, 0, 0, 16);
                    SetLayout(3, 0, 0, 8);
                    SetLayout(4, 0, 0, 32);
                    SetLayout(5, 0, 0, 16);
                    SetLayout(6, 0, 0, 10);
                    SetLayout(7, 0, 0, 11);
                    SetLayout(8, 0, 0, 10);
                    SetLayout(9, 0, 0, 2);
                    SetLayout(10, 0, 0, 8);
                    SetLayout(11, 0, 0, 32);
                    SetLayout(12, 0, 0, 16);
                    SetLayout(13, 0, 0, 32);
                    SetLayout(14, 0, 0, 32);
                    break;
                case 1:
                    SetLayout(3, 1, 0, 8);
                    SetLayout(5, 2, 0, 16);
                    SetLayout(6, 0, 10, 11);
                    SetLayout(7, 0, 11, 11);
                    SetLayout(8, 0, 10, 10);
                    SetLayout(9, 0, 2, 10);
                    SetLayout(10, 1, 0, 8);
                    SetLayout(11, 4, 0, 32);
                    SetLayout(12, 2, 0, 16);
                    SetLayout(13, 4, 0, 32);
                    SetLayout(14, 4, 0, 32);
                    break;
                case 2:
                    SetLayout(6, 0, 21, 11);
                    SetLayout(7, 0, 22, 10);
                    SetLayout(8, 0, 20, 10);
                    SetLayout(9, 0, 12, 10);
                    SetLayout(10, 2, 0, 8);
                    SetLayout(12, 4, 0, 16);
                    SetLayout(13, 8, 0, 32);
                    SetLayout(14, 8, 0, 32);
                    break;
                case 3:
                    SetLayout(8, 0, 30, 2);
                    SetLayout(9, 0, 22, 10);
                    SetLayout(10, 3, 0, 8);
                    SetLayout(12, 6, 0, 16);
                    SetLayout(14, 12, 0, 32);
                    break;
            }

            var valid = _module.AddInstruction(
                SpirvOp.INotEqual,
                _boolType,
                bitCount,
                UInt(0));
            EmitConditional(valid, () =>
            {
                var raw = ConvertGfx10BufferStoreComponentV7608(
                    canonical,
                    bitCount,
                    numberFormat,
                    dataFormat);
                var widthIs32 = _module.AddInstruction(
                    SpirvOp.IEqual,
                    _boolType,
                    bitCount,
                    UInt(32));
                var lowMask = ISubU(ShiftLeftLogical(UInt(1), bitCount), UInt(1));
                lowMask = SelectU(widthIs32, UInt(uint.MaxValue), lowMask);
                var fieldMask = ShiftLeftLogical(lowMask, bitOffset);
                var address = IAdd(elementAddress, byteOffset);
                var previous = LoadUnalignedBufferWord(bindingIndex, address);
                var updated = BitwiseOr(
                    BitwiseAnd(
                        previous,
                        _module.AddInstruction(SpirvOp.Not, _uintType, fieldMask)),
                    ShiftLeftLogical(BitwiseAnd(raw, lowMask), bitOffset));
                StoreGuestBufferDwordV74054(bindingIndex, address, updated);
            });
        }

        private uint ConvertGfx10BufferStoreComponentV7608(
            uint canonical,
            uint bitCount,
            uint numberFormat,
            uint dataFormat)
        {
            var widthIs32 = _module.AddInstruction(
                SpirvOp.IEqual,
                _boolType,
                bitCount,
                UInt(32));
            var lowMask = ISubU(ShiftLeftLogical(UInt(1), bitCount), UInt(1));
            lowMask = SelectU(widthIs32, UInt(uint.MaxValue), lowMask);
            var signedMaximum = ShiftRightLogical(lowMask, UInt(1));
            var signedMinimumBits = _module.AddInstruction(
                SpirvOp.Not,
                _uintType,
                signedMaximum);

            // Integer stores saturate to the representable memory width before
            // truncation. This also keeps OpConvert* away from out-of-range
            // inputs in the scaled/normalized paths.
            var uintValue = SelectU(
                _module.AddInstruction(
                    SpirvOp.UGreaterThan,
                    _boolType,
                    canonical,
                    lowMask),
                lowMask,
                canonical);

            var sourceInt = Bitcast(_intType, canonical);
            var maximumInt = Bitcast(_intType, signedMaximum);
            var minimumInt = Bitcast(_intType, signedMinimumBits);
            var sintHigh = _module.AddInstruction(
                SpirvOp.Select,
                _intType,
                _module.AddInstruction(
                    SpirvOp.SGreaterThan,
                    _boolType,
                    sourceInt,
                    maximumInt),
                maximumInt,
                sourceInt);
            var sintValue = _module.AddInstruction(
                SpirvOp.Select,
                _intType,
                _module.AddInstruction(
                    SpirvOp.SLessThan,
                    _boolType,
                    sintHigh,
                    minimumInt),
                minimumInt,
                sintHigh);
            var sintBits = BitwiseAnd(Bitcast(_uintType, sintValue), lowMask);

            var sourceFloat = Bitcast(_floatType, canonical);
            // Integer/normalized conversions of NaN are otherwise undefined in
            // SPIR-V OpConvertFTo*. Hardware format conversion treats a NaN as
            // a non-numeric value; use zero for those paths while preserving
            // the original bit pattern for FLOAT stores below.
            var numericFloat = _module.AddInstruction(
                SpirvOp.Select,
                _floatType,
                _module.AddInstruction(SpirvOp.IsNan, _boolType, sourceFloat),
                Float(0f),
                sourceFloat);
            var unsignedMaximumFloat = _module.AddInstruction(
                SpirvOp.ConvertUToF,
                _floatType,
                lowMask);
            var signedMaximumFloat = _module.AddInstruction(
                SpirvOp.ConvertSToF,
                _floatType,
                maximumInt);
            var signedMinimumFloat = _module.AddInstruction(
                SpirvOp.ConvertSToF,
                _floatType,
                minimumInt);

            var unormFloat = ClampFloatV7608(numericFloat, Float(0f), Float(1f));
            var unormScaled = _module.AddInstruction(
                SpirvOp.FMul,
                _floatType,
                unormFloat,
                unsignedMaximumFloat);
            var unorm = BitwiseAnd(
                _module.AddInstruction(
                    SpirvOp.ConvertFToU,
                    _uintType,
                    _module.AddInstruction(
                        SpirvOp.FAdd,
                        _floatType,
                        unormScaled,
                        Float(0.5f))),
                lowMask);

            var snormFloat = ClampFloatV7608(numericFloat, Float(-1f), Float(1f));
            var snormScaled = _module.AddInstruction(
                SpirvOp.FMul,
                _floatType,
                snormFloat,
                signedMaximumFloat);
            var snorm = BitwiseAnd(
                Bitcast(
                    _uintType,
                    _module.AddInstruction(
                        SpirvOp.ConvertFToS,
                        _intType,
                        RoundSignedFloatV7608(snormScaled))),
                lowMask);

            var uscaledFloat = ClampFloatV7608(
                numericFloat,
                Float(0f),
                unsignedMaximumFloat);
            var uscaled = BitwiseAnd(
                _module.AddInstruction(
                    SpirvOp.ConvertFToU,
                    _uintType,
                    _module.AddInstruction(
                        SpirvOp.FAdd,
                        _floatType,
                        uscaledFloat,
                        Float(0.5f))),
                lowMask);

            var sscaledFloat = ClampFloatV7608(
                numericFloat,
                signedMinimumFloat,
                signedMaximumFloat);
            var sscaled = BitwiseAnd(
                Bitcast(
                    _uintType,
                    _module.AddInstruction(
                        SpirvOp.ConvertFToS,
                        _intType,
                        RoundSignedFloatV7608(sscaledFloat))),
                lowMask);

            var floating = canonical;
            floating = SelectU(
                _module.AddInstruction(
                    SpirvOp.IEqual,
                    _boolType,
                    bitCount,
                    UInt(16)),
                EmitFloatToHalf(canonical),
                floating);
            var isPackedFloat = _module.AddInstruction(
                SpirvOp.LogicalOr,
                _boolType,
                _module.AddInstruction(
                    SpirvOp.IEqual,
                    _boolType,
                    dataFormat,
                    UInt(6)),
                _module.AddInstruction(
                    SpirvOp.IEqual,
                    _boolType,
                    dataFormat,
                    UInt(7)));
            floating = SelectU(
                isPackedFloat,
                EncodeUnsignedMiniFloatV7608(canonical, bitCount),
                floating);
            floating = BitwiseAnd(floating, lowMask);

            var result = BitwiseAnd(canonical, lowMask);
            result = SelectUInt(numberFormat, 0, unorm, result);
            result = SelectUInt(numberFormat, 1, snorm, result);
            result = SelectUInt(numberFormat, 2, uscaled, result);
            result = SelectUInt(numberFormat, 3, sscaled, result);
            result = SelectUInt(numberFormat, 4, uintValue, result);
            result = SelectUInt(numberFormat, 5, sintBits, result);
            result = SelectUInt(numberFormat, 7, floating, result);
            return result;
        }

        private uint ClampFloatV7608(uint value, uint minimum, uint maximum)
        {
            var lowClamped = _module.AddInstruction(
                SpirvOp.Select,
                _floatType,
                _module.AddInstruction(
                    SpirvOp.FOrdLessThan,
                    _boolType,
                    value,
                    minimum),
                minimum,
                value);
            return _module.AddInstruction(
                SpirvOp.Select,
                _floatType,
                _module.AddInstruction(
                    SpirvOp.FOrdGreaterThan,
                    _boolType,
                    lowClamped,
                    maximum),
                maximum,
                lowClamped);
        }

        private uint RoundSignedFloatV7608(uint value)
        {
            var adjustment = _module.AddInstruction(
                SpirvOp.Select,
                _floatType,
                _module.AddInstruction(
                    SpirvOp.FOrdLessThan,
                    _boolType,
                    value,
                    Float(0f)),
                Float(-0.5f),
                Float(0.5f));
            return _module.AddInstruction(
                SpirvOp.FAdd,
                _floatType,
                value,
                adjustment);
        }

        // 10_11_11 and 11_11_10 FLOAT channels are unsigned mini-floats with
        // the same five-bit exponent/bias as IEEE f16 and a 5/6-bit mantissa.
        // Reuse the already validated f32->f16 RNE conversion, then narrow only
        // the half mantissa with another round-to-nearest-even step.
        private uint EncodeUnsignedMiniFloatV7608(uint floatBits, uint bitCount)
        {
            var half = BitwiseAnd(EmitFloatToHalf(floatBits), UInt(0xFFFF));
            var negative = _module.AddInstruction(
                SpirvOp.INotEqual,
                _boolType,
                BitwiseAnd(half, UInt(0x8000)),
                UInt(0));
            var exponent = BitwiseAnd(
                ShiftRightLogical(half, UInt(10)),
                UInt(0x1F));
            var mantissa = BitwiseAnd(half, UInt(0x3FF));
            var mantissaBits = ISubU(bitCount, UInt(5));
            var drop = ISubU(UInt(10), mantissaBits);
            var quotient = ShiftRightLogical(mantissa, drop);
            var remainderMask = ISubU(ShiftLeftLogical(UInt(1), drop), UInt(1));
            var remainder = BitwiseAnd(mantissa, remainderMask);
            var halfWay = ShiftLeftLogical(UInt(1), ISubU(drop, UInt(1)));
            var roundUp = _module.AddInstruction(
                SpirvOp.LogicalOr,
                _boolType,
                _module.AddInstruction(
                    SpirvOp.UGreaterThan,
                    _boolType,
                    remainder,
                    halfWay),
                _module.AddInstruction(
                    SpirvOp.LogicalAnd,
                    _boolType,
                    _module.AddInstruction(
                        SpirvOp.IEqual,
                        _boolType,
                        remainder,
                        halfWay),
                    _module.AddInstruction(
                        SpirvOp.INotEqual,
                        _boolType,
                        BitwiseAnd(quotient, UInt(1)),
                        UInt(0))));
            var rounded = IAdd(
                quotient,
                SelectU(roundUp, UInt(1), UInt(0)));
            var mantissaMask = ISubU(
                ShiftLeftLogical(UInt(1), mantissaBits),
                UInt(1));
            var carry = ShiftRightLogical(rounded, mantissaBits);
            var isSpecial = _module.AddInstruction(
                SpirvOp.IEqual,
                _boolType,
                exponent,
                UInt(31));
            var finiteExponent = IAdd(exponent, carry);
            finiteExponent = SelectU(
                _module.AddInstruction(
                    SpirvOp.UGreaterThan,
                    _boolType,
                    finiteExponent,
                    UInt(31)),
                UInt(31),
                finiteExponent);
            var finiteMantissa = BitwiseAnd(rounded, mantissaMask);

            var sourceIsNan = _module.AddInstruction(
                SpirvOp.INotEqual,
                _boolType,
                mantissa,
                UInt(0));
            var specialMantissa = BitwiseAnd(quotient, mantissaMask);
            specialMantissa = SelectU(
                _module.AddInstruction(
                    SpirvOp.LogicalAnd,
                    _boolType,
                    sourceIsNan,
                    _module.AddInstruction(
                        SpirvOp.IEqual,
                        _boolType,
                        specialMantissa,
                        UInt(0))),
                UInt(1),
                specialMantissa);
            var outputExponent = SelectU(isSpecial, UInt(31), finiteExponent);
            var outputMantissa = SelectU(isSpecial, specialMantissa, finiteMantissa);
            var encoded = BitwiseOr(
                ShiftLeftLogical(outputExponent, mantissaBits),
                outputMantissa);
            // Unsigned mini-floats clamp negative finite values/-Inf to zero,
            // while preserving a NaN payload regardless of its sign bit.
            var negativeNonNan = _module.AddInstruction(
                SpirvOp.LogicalAnd,
                _boolType,
                negative,
                _module.AddInstruction(
                    SpirvOp.LogicalNot,
                    _boolType,
                    sourceIsNan));
            return SelectU(negativeNonNan, UInt(0), encoded);
        }
    }
}
