// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.4: soft-fail unsupported opcodes so one rare op does not kill the
// entire shader translation (black draws / missing Bink GPU path).

using System.Collections.Concurrent;
using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static readonly bool SoftFailEnabled =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_SHADER_SOFT_FAIL"),
                "0",
                StringComparison.Ordinal);

        private static readonly bool SoftFailTrace =
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_TRACE_SHADER_SOFT_FAIL"),
                "1",
                StringComparison.Ordinal);

        private static readonly ConcurrentDictionary<string, byte> SoftFailSeen = new(StringComparer.Ordinal);

        /// <summary>
        /// When soft-fail is enabled, zeros every destination VGPR/SGPR and
        /// returns true so translation continues. Otherwise returns false.
        /// </summary>
        private bool TrySoftFailInstruction(
            Gen5ShaderInstruction instruction,
            string reason,
            out string error)
        {
            error = string.Empty;
            if (!SoftFailEnabled)
            {
                error = reason;
                return false;
            }

            if (SoftFailTrace)
            {
                var key = $"{_stage}:{instruction.Opcode}";
                if (SoftFailSeen.TryAdd(key, 0))
                {
                    Console.Error.WriteLine(
                        $"[SHADER-SOFT-FAIL][V76.0.4] stage={_stage} " +
                        $"pc=0x{instruction.Pc:X} op={instruction.Opcode} reason={reason}");
                }
            }

            foreach (var dest in instruction.Destinations)
            {
                if (dest.Kind == Gen5OperandKind.VectorRegister)
                {
                    StoreV(dest.Value, UInt(0));
                }
                else if (dest.Kind == Gen5OperandKind.ScalarRegister)
                {
                    StoreS(dest.Value, UInt(0));
                }
            }

            return true;
        }
    }
}
