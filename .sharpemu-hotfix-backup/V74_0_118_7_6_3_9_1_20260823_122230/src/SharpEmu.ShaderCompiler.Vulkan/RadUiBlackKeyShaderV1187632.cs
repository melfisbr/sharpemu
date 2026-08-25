// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// SHARPEMU_V74_0_118_7_6_3_8_MENU_LUMA_KEY_SHADER

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
            var values =
                new uint[2 + operands.Length];
            values[0] = glsl;
            values[1] = operation;
            operands.CopyTo(values, 2);
            return module.AddInstruction(
                SpirvOp.ExtInst,
                resultType,
                values);
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
            module.AddInstruction(
                SpirvOp.ImageSampleExplicitLod,
                vec4Type,
                sampledImage,
                coordinates,
                2,
                Float(0f));

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

        // Hard spatial isolation now belongs to the Vulkan pipeline scissor.
        // Inside that region retain ordinary menu luminance instead of the
        // strict V3.7.1 neutral/green classifier which removed menu glyphs.
        var maxRg =
            Ext(
                40, // GLSL.std.450 FMax
                floatType,
                red,
                green);
        var maxRgb =
            Ext(
                40,
                floatType,
                maxRg,
                blue);
        var shifted =
            module.AddInstruction(
                SpirvOp.FSub,
                floatType,
                maxRgb,
                Float(0.055f));
        var normalized =
            module.AddInstruction(
                SpirvOp.FDiv,
                floatType,
                shifted,
                Float(0.175f));
        var alpha =
            Ext(
                43, // GLSL.std.450 FClamp
                floatType,
                normalized,
                Float(0f),
                Float(1f));

        // Keep the guest overlay near its source color while avoiding the
        // neon amplification observed in the V3.6 full-frame leak.
        var outRed =
            module.AddInstruction(
                SpirvOp.FMul,
                floatType,
                red,
                Float(0.92f));
        var outGreen =
            module.AddInstruction(
                SpirvOp.FMul,
                floatType,
                green,
                Float(0.88f));
        var outBlue =
            module.AddInstruction(
                SpirvOp.FMul,
                floatType,
                blue,
                Float(0.92f));

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
