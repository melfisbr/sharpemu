// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using SharpEmu.Libs.Gpu;
using SharpEmu.ShaderCompiler;

namespace SharpEmu.Libs.Agc;

public static partial class AgcExports
{
    private static readonly bool ParallelVulkanStageCompileV7611 =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_VK_PARALLEL_STAGE_COMPILE"),
            "0",
            StringComparison.Ordinal) &&
        Environment.ProcessorCount >= 4;

    private static readonly bool TraceParallelVulkanStageCompileV7611 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_TRACE_SHADER_PIPELINE_TIMING"),
            "1",
            StringComparison.Ordinal);

    private static long _parallelStagePairsV7611;
    private static long _parallelStageFailuresV7611;

    private static bool TryCompileGraphicsShaderPairV7611(
        Gen5ShaderState pixelState,
        Gen5ShaderEvaluation pixelEvaluation,
        IReadOnlyList<Gen5PixelOutputBinding> pixelOutputs,
        Gen5ShaderState exportState,
        Gen5ShaderEvaluation exportEvaluation,
        int guestGlobalBuffers,
        int totalGlobalBuffers,
        uint psInputEna,
        uint psInputAddr,
        IReadOnlyList<uint>? psInputCntl,
        uint requiredVertexOutputCount,
        out IGuestCompiledShader? vertexShader,
        out IGuestCompiledShader? pixelShader,
        out string error)
    {
        // V76.0.11.1: definite-assignment BuildFix for short-circuit fallback paths.
        vertexShader = null;
        pixelShader = null;
        error = string.Empty;

        var backend = GuestGpu.Current;
        var useParallel = ParallelVulkanStageCompileV7611 &&
            string.Equals(backend.BackendName, "Vulkan", StringComparison.Ordinal);

        if (!useParallel)
        {
            if (!backend.TryCompilePixelShader(
                    pixelState,
                    pixelEvaluation,
                    pixelOutputs,
                    out pixelShader,
                    out error,
                    globalBufferBase: 0,
                    totalGlobalBufferCount: totalGlobalBuffers,
                    imageBindingBase: 0,
                    scalarRegisterBufferIndex: _bakeScalars ? -1 : guestGlobalBuffers,
                    pixelInputEnable: psInputEna,
                    pixelInputAddress: psInputAddr,
                    pixelInputCntl: psInputCntl,
                    storageBufferOffsetAlignment: _storageBufferOffsetAlignment) ||
                !backend.TryCompileVertexShader(
                    exportState,
                    exportEvaluation,
                    out vertexShader,
                    out error,
                    globalBufferBase: pixelEvaluation.GlobalMemoryBindings.Count,
                    totalGlobalBufferCount: totalGlobalBuffers,
                    imageBindingBase: pixelEvaluation.ImageBindings.Count,
                    scalarRegisterBufferIndex: _bakeScalars ? -1 : guestGlobalBuffers + 1,
                    requiredVertexOutputCount: (int)requiredVertexOutputCount,
                    storageBufferOffsetAlignment: _storageBufferOffsetAlignment))
            {
                return false;
            }

            return true;
        }

        var started = TraceParallelVulkanStageCompileV7611
            ? Stopwatch.GetTimestamp()
            : 0L;

        (bool Success, IGuestCompiledShader? Shader, string Error) CompilePixel()
        {
            var success = backend.TryCompilePixelShader(
                pixelState,
                pixelEvaluation,
                pixelOutputs,
                out var shader,
                out var compileError,
                globalBufferBase: 0,
                totalGlobalBufferCount: totalGlobalBuffers,
                imageBindingBase: 0,
                scalarRegisterBufferIndex: _bakeScalars ? -1 : guestGlobalBuffers,
                pixelInputEnable: psInputEna,
                pixelInputAddress: psInputAddr,
                pixelInputCntl: psInputCntl,
                storageBufferOffsetAlignment: _storageBufferOffsetAlignment);
            return (success, shader, compileError);
        }

        (bool Success, IGuestCompiledShader? Shader, string Error) CompileVertex()
        {
            var success = backend.TryCompileVertexShader(
                exportState,
                exportEvaluation,
                out var shader,
                out var compileError,
                globalBufferBase: pixelEvaluation.GlobalMemoryBindings.Count,
                totalGlobalBufferCount: totalGlobalBuffers,
                imageBindingBase: pixelEvaluation.ImageBindings.Count,
                scalarRegisterBufferIndex: _bakeScalars ? -1 : guestGlobalBuffers + 1,
                requiredVertexOutputCount: (int)requiredVertexOutputCount,
                storageBufferOffsetAlignment: _storageBufferOffsetAlignment);
            return (success, shader, compileError);
        }

        try
        {
            var pixelTask = Task.Run(CompilePixel);
            var vertexTask = Task.Run(CompileVertex);
            Task.WaitAll(pixelTask, vertexTask);

            var pixelResult = pixelTask.Result;
            var vertexResult = vertexTask.Result;
            pixelShader = pixelResult.Shader;
            vertexShader = vertexResult.Shader;
            if (!pixelResult.Success || !vertexResult.Success)
            {
                Interlocked.Increment(ref _parallelStageFailuresV7611);
                error = !pixelResult.Success
                    ? pixelResult.Error
                    : vertexResult.Error;
                return false;
            }

            error = string.Empty;
            var pairCount = Interlocked.Increment(ref _parallelStagePairsV7611);
            if (TraceParallelVulkanStageCompileV7611 && started != 0)
            {
                var elapsedMs = (Stopwatch.GetTimestamp() - started) *
                    1000.0 / Stopwatch.Frequency;
                Console.Error.WriteLine(
                    $"[V76.0.11][PARALLEL_STAGE_COMPILE] pair={pairCount} " +
                    $"ms={elapsedMs:F3} vs=0x{exportState.Program.Address:X16} " +
                    $"ps=0x{pixelState.Program.Address:X16}");
            }
            return true;
        }
        catch (AggregateException aggregate)
        {
            vertexShader = null;
            pixelShader = null;
            Interlocked.Increment(ref _parallelStageFailuresV7611);
            var flattened = aggregate.Flatten();
            error = flattened.InnerExceptions.Count == 0
                ? "parallel Vulkan shader stage compilation failed"
                : $"parallel Vulkan shader stage compilation failed: {flattened.InnerExceptions[0].Message}";
            return false;
        }
    }
}
