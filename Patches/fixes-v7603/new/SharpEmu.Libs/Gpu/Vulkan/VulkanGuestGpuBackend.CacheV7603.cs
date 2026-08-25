// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.3: cached wrappers matching VulkanGuestGpuBackend compile signatures.

using SharpEmu.ShaderCompiler;
using SharpEmu.ShaderCompiler.Vulkan;

namespace SharpEmu.Libs.Gpu.Vulkan;

internal static class VulkanShaderCompileCacheV7603
{
    internal static bool TryCompileVertexCached(
        Gen5ShaderState state,
        Gen5ShaderEvaluation evaluation,
        out Gen5SpirvShader shader,
        out string error,
        int globalBufferBase,
        int totalGlobalBufferCount,
        int imageBindingBase,
        int scalarRegisterBufferIndex,
        int requiredVertexOutputCount,
        ulong storageBufferOffsetAlignment)
    {
        var key = Gen5SpirvTranslator.BuildCompileCacheKey(
            "VS",
            state,
            $"gbb={globalBufferBase}|tgb={totalGlobalBufferCount}|ibb={imageBindingBase}|sr={scalarRegisterBufferIndex}|vo={requiredVertexOutputCount}|align={storageBufferOffsetAlignment}");

        if (Gen5SpirvTranslator.TryGetCachedShader(key, out shader))
        {
            error = string.Empty;
            return true;
        }

        var ok = Gen5SpirvTranslator.TryCompileVertexShader(
            state,
            evaluation,
            out shader,
            out error,
            globalBufferBase,
            totalGlobalBufferCount,
            imageBindingBase,
            scalarRegisterBufferIndex,
            requiredVertexOutputCount,
            storageBufferOffsetAlignment);

        if (ok)
        {
            Gen5SpirvTranslator.StoreCachedShader(key, shader);
        }

        return ok;
    }

    internal static bool TryCompilePixelCached(
        Gen5ShaderState state,
        Gen5ShaderEvaluation evaluation,
        IReadOnlyList<Gen5PixelOutputBinding> outputs,
        out Gen5SpirvShader shader,
        out string error,
        int globalBufferBase,
        int totalGlobalBufferCount,
        int imageBindingBase,
        int scalarRegisterBufferIndex,
        uint pixelInputEnable,
        uint pixelInputAddress,
        IReadOnlyList<uint>? pixelInputCntl,
        ulong storageBufferOffsetAlignment)
    {
        var outFp = string.Join(',', outputs.Select(o => $"{o.GuestSlot}:{o.HostLocation}:{(int)o.Kind}"));
        var key = Gen5SpirvTranslator.BuildCompileCacheKey(
            "PS",
            state,
            $"gbb={globalBufferBase}|tgb={totalGlobalBufferCount}|ibb={imageBindingBase}|sr={scalarRegisterBufferIndex}|pe={pixelInputEnable:X}|pa={pixelInputAddress:X}|out={outFp}|align={storageBufferOffsetAlignment}");

        if (Gen5SpirvTranslator.TryGetCachedShader(key, out shader))
        {
            error = string.Empty;
            return true;
        }

        var ok = Gen5SpirvTranslator.TryCompilePixelShader(
            state,
            evaluation,
            outputs,
            out shader,
            out error,
            globalBufferBase,
            totalGlobalBufferCount,
            imageBindingBase,
            scalarRegisterBufferIndex,
            pixelInputEnable,
            pixelInputAddress,
            pixelInputCntl,
            storageBufferOffsetAlignment);

        if (ok)
        {
            Gen5SpirvTranslator.StoreCachedShader(key, shader);
        }

        return ok;
    }

    internal static bool TryCompileComputeCached(
        Gen5ShaderState state,
        Gen5ShaderEvaluation evaluation,
        uint localSizeX,
        uint localSizeY,
        uint localSizeZ,
        out Gen5SpirvShader shader,
        out string error,
        int totalGlobalBufferCount,
        int initialScalarBufferIndex,
        uint waveLaneCount,
        ulong storageBufferOffsetAlignment)
    {
        var key = Gen5SpirvTranslator.BuildCompileCacheKey(
            "CS",
            state,
            $"lx={localSizeX}|ly={localSizeY}|lz={localSizeZ}|tgb={totalGlobalBufferCount}|sr={initialScalarBufferIndex}|wave={waveLaneCount}|align={storageBufferOffsetAlignment}");

        if (Gen5SpirvTranslator.TryGetCachedShader(key, out shader))
        {
            error = string.Empty;
            return true;
        }

        var ok = Gen5SpirvTranslator.TryCompileComputeShader(
            state,
            evaluation,
            localSizeX,
            localSizeY,
            localSizeZ,
            out shader,
            out error,
            totalGlobalBufferCount,
            initialScalarBufferIndex,
            waveLaneCount,
            storageBufferOffsetAlignment);

        if (ok)
        {
            Gen5SpirvTranslator.StoreCachedShader(key, shader);
        }

        return ok;
    }
}
