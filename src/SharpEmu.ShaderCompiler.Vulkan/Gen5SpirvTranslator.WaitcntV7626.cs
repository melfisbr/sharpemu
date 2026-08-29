// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static readonly ConcurrentDictionary<string, byte> WaitcntTraceSeenV7626 =
            new(StringComparer.Ordinal);

        private bool TryEmitWaitcntV7626(
            Gen5ShaderInstruction instruction,
            out string error)
        {
            error = string.Empty;
            if (instruction.Control is not Gen5WaitcntControl wait)
            {
                return false;
            }

            // S_WAITCNT_DEPCTR is a dependency-scoreboard wait for VA/VM
            // source/destination hazards. Those register dependencies are
            // represented by the translated SPIR-V SSA graph. It is not an
            // inter-wave memory barrier, so keep it execution-neutral while
            // retaining explicit Bink telemetry.
            if (wait.Kind == Gen5WaitcntKind.Dependency)
            {
                TraceWaitcntV7626(instruction, wait, "ssa-dependency");
                return true;
            }

            var waitDeviceMemory = false;
            var waitWorkgroupMemory = false;

            if (wait.Kind == Gen5WaitcntKind.Combined)
            {
                var vmcnt = ((wait.Immediate >> 14) & 0x3) << 4 |
                            (wait.Immediate & 0xF);
                var expcnt = (wait.Immediate >> 4) & 0x7;
                var lgkmcnt = (wait.Immediate >> 8) & 0x3F;

                // Maximum encoded thresholds mean "do not wait" for that
                // counter. Any lower threshold is conservatively represented
                // as a SPIR-V memory-order point. SPIR-V cannot expose AMD's
                // outstanding-operation counters directly, so this is stronger
                // than the native threshold but preserves correctness/order.
                waitDeviceMemory = vmcnt < 0x3F || expcnt < 0x7;
                waitWorkgroupMemory = lgkmcnt < 0x3F;
            }
            else
            {
                waitDeviceMemory = wait.Kind is
                    Gen5WaitcntKind.VectorStore or
                    Gen5WaitcntKind.VectorMemory or
                    Gen5WaitcntKind.Export;
                waitWorkgroupMemory = wait.Kind == Gen5WaitcntKind.Lgkm;
            }

            // StorageBuffer/Uniform and image operations live at Device scope.
            // AcquireRelease is deliberately conservative: S_WAITCNT is a
            // completion/order instruction, not a cross-invocation execution
            // barrier, so do not emit OpControlBarrier here.
            if (waitDeviceMemory)
            {
                _module.AddStatement(
                    SpirvOp.MemoryBarrier,
                    UInt(1), // Device
                    UInt(0x848)); // AcquireRelease | UniformMemory | ImageMemory
            }

            if (waitWorkgroupMemory)
            {
                if (_stage == Gen5SpirvStage.Compute)
                {
                    _module.AddStatement(
                        SpirvOp.MemoryBarrier,
                        UInt(2), // Workgroup
                        UInt(0x108)); // AcquireRelease | WorkgroupMemory
                }

                // LGKMCNT also covers scalar-memory traffic; order translated
                // StorageBuffer/Uniform accesses at Device scope as well.
                _module.AddStatement(
                    SpirvOp.MemoryBarrier,
                    UInt(1), // Device
                    UInt(0x48)); // AcquireRelease | UniformMemory
            }

            TraceWaitcntV7626(
                instruction,
                wait,
                waitDeviceMemory || waitWorkgroupMemory
                    ? "memory-order"
                    : "threshold-noop");
            return true;
        }

        private void TraceWaitcntV7626(
            Gen5ShaderInstruction instruction,
            Gen5WaitcntControl wait,
            string action)
        {
            if (_stage != Gen5SpirvStage.Compute ||
                !string.Equals(
                    Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE"),
                    "guest",
                    StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var key =
                $"{_state.Program.Address:X16}:{instruction.Pc:X}:{wait.Kind}:" +
                $"{wait.Immediate:X4}:{wait.ScalarThresholdRegister}:{action}";
            if (!WaitcntTraceSeenV7626.TryAdd(key, 0))
            {
                return;
            }

            Console.Error.WriteLine(
                "[BINK-GUEST][V76.2.6][WAITCNT] " +
                $"shader=0x{_state.Program.Address:X16} pc=0x{instruction.Pc:X} " +
                $"kind={wait.Kind} imm=0x{wait.Immediate:X4} " +
                $"sgpr={(wait.ScalarThresholdRegister?.ToString() ?? "null")} " +
                $"action={action}");
        }
    }
}
