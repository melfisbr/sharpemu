// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// SHARPEMU_V74_0_118_7_6_3_9_GLYPH_PRESERVE_SHADER

namespace SharpEmu.ShaderCompiler.Vulkan;

public static class RadUiBlackKeyShaderV1187632
{
    public static byte[] Create()
    {
        var module = new SpirvModuleBuilder();
        module.AddCapability(SpirvCapability.Shader);
        var glsl = module.ImportExtInst("GLSL.std.450");

        var voidType = module.TypeVoid();
        var floatType = module.TypeFloat(32);
        var vec2Type = module.TypeVector(floatType, 2);
        var vec4Type = module.TypeVector(floatType, 4);
        var inputVec4Pointer =
            module.TypePointer(
                SpirvStorageClass.Input,
                vec4Type);
        var outputVec4Pointer =
            module.TypePointer(
                SpirvStorageClass.Output,
                vec4Type);
        var imageType = module.TypeImage(
            floatType,
            SpirvImageDim.Dim2D,
            depth: false,
            arrayed: false,
            multisampled: false,
            sampled: 1,
            SpirvImageFormat.Unknown);
        var sampledImageType =
            module.TypeSampledImage(imageType);
        var sampledImagePointer =
            module.TypePointer(
                SpirvStorageClass.UniformConstant,
                sampledImageType);

        var attribute =
            module.AddGlobalVariable(
                inputVec4Pointer,
                SpirvStorageClass.Input);
        module.AddDecoration(
            attribute,
            SpirvDecoration.Location,
            0);

        var texture =
            module.AddGlobalVariable(
                sampledImagePointer,
                SpirvStorageClass.UniformConstant);
        module.AddDecoration(
            texture,
            SpirvDecoration.DescriptorSet,
            0);
        module.AddDecoration(
            texture,
            SpirvDecoration.Binding,
            1);

        var output =
            module.AddGlobalVariable(
                outputVec4Pointer,
                SpirvStorageClass.Output);
        module.AddDecoration(
            output,
            SpirvDecoration.Location,
            0);

        uint Float(float value) =>
            module.ConstantFloat(floatType, value);

        uint Ext(
            uint operation,
            uint resultType,
            params uint[] operands)
        {
            var values = new uint[2 + operands.Length];
            values[0] = glsl;
            values[1] = operation;
            operands.CopyTo(values, 2);
            return module.AddInstruction(
                SpirvOp.ExtInst,
                resultType,
                values);
        }

        uint Max(uint left, uint right) =>
            Ext(
                40, // GLSL.std.450 FMax
                floatType,
                left,
                right);

        uint Min(uint left, uint right) =>
            Ext(
                37, // GLSL.std.450 FMin
                floatType,
                left,
                right);

        uint Clamp01(uint value) =>
            Ext(
                43, // GLSL.std.450 FClamp
                floatType,
                value,
                Float(0f),
                Float(1f));

        uint LumaMax(uint color)
        {
            var r =
                module.AddInstruction(
                    SpirvOp.CompositeExtract,
                    floatType,
                    color,
                    0);
            var g =
                module.AddInstruction(
                    SpirvOp.CompositeExtract,
                    floatType,
                    color,
                    1);
            var b =
                module.AddInstruction(
                    SpirvOp.CompositeExtract,
                    floatType,
                    color,
                    2);
            return Max(Max(r, g), b);
        }

        uint SampleAt(
            uint sampledImage,
            uint coordinates)
        {
            return module.AddInstruction(
                SpirvOp.ImageSampleExplicitLod,
                vec4Type,
                sampledImage,
                coordinates,
                2,
                Float(0f));
        }

        uint OffsetCoordinates(
            uint coordinates,
            float dx,
            float dy)
        {
            var offset =
                module.AddInstruction(
                    SpirvOp.CompositeConstruct,
                    vec2Type,
                    Float(dx),
                    Float(dy));
            return module.AddInstruction(
                SpirvOp.FAdd,
                vec2Type,
                coordinates,
                offset);
        }

        var functionType =
            module.TypeFunction(voidType);
        var main =
            module.BeginFunction(
                voidType,
                functionType);
        module.AddLabel();

        var attributeValue =
            module.AddInstruction(
                SpirvOp.Load,
                vec4Type,
                attribute);
        var coordinates =
            module.AddInstruction(
                SpirvOp.VectorShuffle,
                vec2Type,
                attributeValue,
                attributeValue,
                0,
                1);
        var sampledImage =
            module.AddInstruction(
                SpirvOp.Load,
                sampledImageType,
                texture);

        var color =
            SampleAt(
                sampledImage,
                coordinates);

        var red =
            module.AddInstruction(
                SpirvOp.CompositeExtract,
                floatType,
                color,
                0);
        var green =
            module.AddInstruction(
                SpirvOp.CompositeExtract,
                floatType,
                color,
                1);
        var blue =
            module.AddInstruction(
                SpirvOp.CompositeExtract,
                floatType,
                color,
                2);

        var centerMax =
            Max(
                Max(red, green),
                blue);
        var centerMin =
            Min(
                Min(red, green),
                blue);
        var saturation =
            module.AddInstruction(
                SpirvOp.FSub,
                floatType,
                centerMax,
                centerMin);

        // V3.8 showed the selected highlight but not its label. The selected
        // label uses dark glyphs cut into a bright white/green pill, therefore
        // an alpha derived only from the CENTER pixel makes the glyph holes
        // transparent. Build alpha from a small neighborhood while keeping the
        // output RGB from the center pixel. Dark glyphs inside a bright UI
        // element are therefore preserved as opaque dark text.
        var neighborhood =
            centerMax;

        var sample1 =
            SampleAt(
                sampledImage,
                OffsetCoordinates(
                    coordinates,
                    0.0030f,
                    0f));
        neighborhood =
            Max(
                neighborhood,
                LumaMax(sample1));

        var sample2 =
            SampleAt(
                sampledImage,
                OffsetCoordinates(
                    coordinates,
                    -0.0030f,
                    0f));
        neighborhood =
            Max(
                neighborhood,
                LumaMax(sample2));

        var sample3 =
            SampleAt(
                sampledImage,
                OffsetCoordinates(
                    coordinates,
                    0f,
                    0.0040f));
        neighborhood =
            Max(
                neighborhood,
                LumaMax(sample3));

        var sample4 =
            SampleAt(
                sampledImage,
                OffsetCoordinates(
                    coordinates,
                    0f,
                    -0.0040f));
        neighborhood =
            Max(
                neighborhood,
                LumaMax(sample4));

        var sample5 =
            SampleAt(
                sampledImage,
                OffsetCoordinates(
                    coordinates,
                    0.0022f,
                    0.0030f));
        neighborhood =
            Max(
                neighborhood,
                LumaMax(sample5));

        var sample6 =
            SampleAt(
                sampledImage,
                OffsetCoordinates(
                    coordinates,
                    -0.0022f,
                    -0.0030f));
        neighborhood =
            Max(
                neighborhood,
                LumaMax(sample6));

        var support =
            Clamp01(
                module.AddInstruction(
                    SpirvOp.FDiv,
                    floatType,
                    module.AddInstruction(
                        SpirvOp.FSub,
                        floatType,
                        neighborhood,
                        Float(0.060f)),
                    Float(0.115f)));

        // Neutral/low-saturation pixels cover the white/gray labels and the
        // black selected glyph itself. Permit a controlled green accent for
        // the selection glow without accepting the green movie background.
        var neutral =
            Clamp01(
                module.AddInstruction(
                    SpirvOp.FDiv,
                    floatType,
                    module.AddInstruction(
                        SpirvOp.FSub,
                        floatType,
                        Float(0.16f),
                        saturation),
                    Float(0.11f)));

        var maxRb =
            Max(
                red,
                blue);
        var greenLead =
            module.AddInstruction(
                SpirvOp.FSub,
                floatType,
                green,
                maxRb);
        var greenAccent =
            Clamp01(
                module.AddInstruction(
                    SpirvOp.FDiv,
                    floatType,
                    module.AddInstruction(
                        SpirvOp.FSub,
                        floatType,
                        greenLead,
                        Float(0.055f)),
                    Float(0.12f)));

        var classMask =
            Clamp01(
                module.AddInstruction(
                    SpirvOp.FAdd,
                    floatType,
                    neutral,
                    module.AddInstruction(
                        SpirvOp.FMul,
                        floatType,
                        greenAccent,
                        Float(0.55f))));

        var alpha =
            Clamp01(
                module.AddInstruction(
                    SpirvOp.FMul,
                    floatType,
                    support,
                    classMask));

        var outRed =
            module.AddInstruction(
                SpirvOp.FMul,
                floatType,
                red,
                Float(0.96f));
        var outGreen =
            module.AddInstruction(
                SpirvOp.FMul,
                floatType,
                green,
                Float(0.94f));
        var outBlue =
            module.AddInstruction(
                SpirvOp.FMul,
                floatType,
                blue,
                Float(0.96f));

        var keyedColor =
            module.AddInstruction(
                SpirvOp.CompositeConstruct,
                vec4Type,
                outRed,
                outGreen,
                outBlue,
                alpha);

        module.AddStatement(
            SpirvOp.Store,
            output,
            keyedColor);
        module.AddStatement(
            SpirvOp.Return);
        module.EndFunction();

        module.AddEntryPoint(
            SpirvExecutionModel.Fragment,
            main,
            "main",
            [attribute, texture, output]);
        module.AddExecutionMode(
            main,
            SpirvExecutionMode.OriginUpperLeft);
        return module.Build();
    }
}
