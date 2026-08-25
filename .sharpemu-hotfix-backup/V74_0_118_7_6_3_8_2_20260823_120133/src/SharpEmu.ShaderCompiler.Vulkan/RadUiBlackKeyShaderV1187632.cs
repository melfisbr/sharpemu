// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// SHARPEMU_V74_0_118_7_6_3_7_MAIN_MENU_WINDOW_KEY_SHADER

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
        var inputVec4Pointer = module.TypePointer(SpirvStorageClass.Input, vec4Type);
        var outputVec4Pointer = module.TypePointer(SpirvStorageClass.Output, vec4Type);
        var imageType = module.TypeImage(floatType, SpirvImageDim.Dim2D, depth: false, arrayed: false, multisampled: false, sampled: 1, SpirvImageFormat.Unknown);
        var sampledImageType = module.TypeSampledImage(imageType);
        var sampledImagePointer = module.TypePointer(SpirvStorageClass.UniformConstant, sampledImageType);

        var attribute = module.AddGlobalVariable(inputVec4Pointer, SpirvStorageClass.Input);
        module.AddDecoration(attribute, SpirvDecoration.Location, 0);

        var texture = module.AddGlobalVariable(sampledImagePointer, SpirvStorageClass.UniformConstant);
        module.AddDecoration(texture, SpirvDecoration.DescriptorSet, 0);
        module.AddDecoration(texture, SpirvDecoration.Binding, 1);

        var output = module.AddGlobalVariable(outputVec4Pointer, SpirvStorageClass.Output);
        module.AddDecoration(output, SpirvDecoration.Location, 0);

        uint Float(float value) => module.ConstantFloat(floatType, value);
        uint Ext(uint operation, uint resultType, params uint[] operands)
        {
            var values = new uint[2 + operands.Length];
            values[0] = glsl;
            values[1] = operation;
            operands.CopyTo(values, 2);
            return module.AddInstruction(SpirvOp.ExtInst, resultType, values);
        }
        uint Clamp01(uint value) => Ext(43, floatType, value, Float(0f), Float(1f)); // FClamp

        var functionType = module.TypeFunction(voidType);
        var main = module.BeginFunction(voidType, functionType);
        module.AddLabel();

        var attributeValue = module.AddInstruction(SpirvOp.Load, vec4Type, attribute);
        var coordinates = module.AddInstruction(SpirvOp.VectorShuffle, vec2Type, attributeValue, attributeValue, 0, 1);
        var sampledImage = module.AddInstruction(SpirvOp.Load, sampledImageType, texture);
        var color = module.AddInstruction(SpirvOp.ImageSampleExplicitLod, vec4Type, sampledImage, coordinates, 2, Float(0f));

        var x = module.AddInstruction(SpirvOp.CompositeExtract, floatType, coordinates, 0);
        var y = module.AddInstruction(SpirvOp.CompositeExtract, floatType, coordinates, 1);
        var red = module.AddInstruction(SpirvOp.CompositeExtract, floatType, color, 0);
        var green = module.AddInstruction(SpirvOp.CompositeExtract, floatType, color, 1);
        var blue = module.AddInstruction(SpirvOp.CompositeExtract, floatType, color, 2);

        // GLSL.std.450: FMin=37, FMax=40, FClamp=43.
        var maxRb = Ext(40, floatType, red, blue);
        var maxRgb = Ext(40, floatType, maxRb, green);
        var minRb = Ext(37, floatType, red, blue);
        var minRgb = Ext(37, floatType, minRb, green);
        var saturation = module.AddInstruction(SpirvOp.FSub, floatType, maxRgb, minRgb);

        // The resolved source is a full guest main_menu frame, not a black-backed UI-only plate.
        // Restrict extraction to the left menu window plus the bottom copyright strip.
        var leftMask = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, Float(0.44f), x), Float(0.08f)));
        var menuYTop = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, y, Float(0.18f)), Float(0.06f)));
        var menuYBottom = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, Float(0.68f), y), Float(0.08f)));
        var menuWindow = module.AddInstruction(SpirvOp.FMul, floatType, leftMask, module.AddInstruction(SpirvOp.FMul, floatType, menuYTop, menuYBottom));
        var bottomWindow = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, y, Float(0.93f)), Float(0.03f)));

        var neutralMask = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, Float(0.22f), saturation), Float(0.18f)));
        var brightMask = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, maxRgb, Float(0.56f)), Float(0.22f)));
        var whiteMenu = module.AddInstruction(SpirvOp.FMul, floatType, menuWindow, module.AddInstruction(SpirvOp.FMul, floatType, neutralMask, brightMask));

        var greenLead = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, module.AddInstruction(SpirvOp.FSub, floatType, green, maxRb), Float(0.04f)), Float(0.10f)));
        var greenBright = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, green, Float(0.42f)), Float(0.25f)));
        var greenAccent = module.AddInstruction(SpirvOp.FMul, floatType, menuWindow, module.AddInstruction(SpirvOp.FMul, floatType, module.AddInstruction(SpirvOp.FMul, floatType, greenLead, greenBright), Float(0.85f)));

        var bottomBright = Clamp01(module.AddInstruction(SpirvOp.FDiv, floatType, module.AddInstruction(SpirvOp.FSub, floatType, maxRgb, Float(0.65f)), Float(0.18f)));
        var bottomText = module.AddInstruction(SpirvOp.FMul, floatType, bottomWindow, module.AddInstruction(SpirvOp.FMul, floatType, neutralMask, bottomBright));

        var combined = module.AddInstruction(SpirvOp.FAdd, floatType, whiteMenu, module.AddInstruction(SpirvOp.FAdd, floatType, greenAccent, bottomText));
        var alpha = Clamp01(combined);

        // Slightly tame neon before alpha blending over the official RAD movie.
        var outRed = module.AddInstruction(SpirvOp.FMul, floatType, red, Float(0.92f));
        var outGreen = module.AddInstruction(SpirvOp.FMul, floatType, green, Float(0.90f));
        var outBlue = module.AddInstruction(SpirvOp.FMul, floatType, blue, Float(0.92f));

        var keyedColor = module.AddInstruction(SpirvOp.CompositeConstruct, vec4Type, outRed, outGreen, outBlue, alpha);
        module.AddStatement(SpirvOp.Store, output, keyedColor);
        module.AddStatement(SpirvOp.Return);
        module.EndFunction();

        module.AddEntryPoint(SpirvExecutionModel.Fragment, main, "main", [attribute, texture, output]);
        module.AddExecutionMode(main, SpirvExecutionMode.OriginUpperLeft);
        return module.Build();
    }
}
