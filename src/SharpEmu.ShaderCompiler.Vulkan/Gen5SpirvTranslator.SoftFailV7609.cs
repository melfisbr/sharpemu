// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

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

        private static readonly ConcurrentDictionary<string, byte> SoftFailSeen =
            new(StringComparer.Ordinal);

        private bool IsGuestBinkComputeModeV7624151()
        {
            // V76.2.4.15.1: do not depend on BinkGuestOwnedRuntimeV7600.cs.
            // The user's active source carries a newer revision of that lifetime
            // file, so the compiler keys off the already-established hard guest
            // mode plus strict guest GPU policy. This preserves that newer source
            // while still making ISA soft-fail behavior deterministic for Bink.
            return _stage == Gen5SpirvStage.Compute &&
                string.Equals(
                    Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE"),
                    "guest",
                    StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(
                    Environment.GetEnvironmentVariable(
                        "SHARPEMU_BINK_GUEST_STRICT_GPU"),
                    "0",
                    StringComparison.Ordinal);
        }

        private static string GetGuestBinkIsaGapModeV7624151()
        {
            var mode = Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_ISA_GAP_MODE");
            return string.IsNullOrWhiteSpace(mode)
                ? "preserve"
                : mode.Trim().ToLowerInvariant();
        }

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

            // V76.2.4.15.1: do not silently corrupt a guest Bink compute decoder.
            // The legacy soft-fail path zeroes every destination register and then
            // reports translation success. That is especially destructive for a
            // multi-pass video decoder because a single unsupported ALU/load can
            // poison all later Y/UV passes while Vulkan sees a valid pipeline.
            //
            // In hard guest-Bink mode with strict guest GPU ordering, the default is a
            // state-preserving NOP: keep destination registers untouched and emit
            // exact telemetry. This is safer than synthesizing zero and exposes
            // the real GFX10 ISA gaps without enabling a host decoder.
            //
            // Diagnostic modes:
            //   preserve (default) = keep destination state, continue translation
            //   fail               = fail translation at the exact unsupported op
            //   zero               = explicit legacy zero-clobber behavior
            if (IsGuestBinkComputeModeV7624151())
            {
                var mode = GetGuestBinkIsaGapModeV7624151();
                var failTranslation =
                    string.Equals(mode, "fail", StringComparison.Ordinal);
                var legacyZero =
                    string.Equals(mode, "zero", StringComparison.Ordinal);
                var action = failTranslation
                    ? "fail-translation"
                    : legacyZero
                        ? "legacy-zero"
                        : "preserve-destination";

                var key =
                    $"BINK:{_state.Program.Address:X16}:{instruction.Pc:X}:" +
                    $"{instruction.Opcode}:{action}";
                if (SoftFailSeen.TryAdd(key, 0))
                {
                    Console.Error.WriteLine(
                        "[BINK-GUEST][V76.2.4.15.1][ISA-GAP] " +
                        $"shader=0x{_state.Program.Address:X16} stage={_stage} " +
                        $"pc=0x{instruction.Pc:X} op={instruction.Opcode} " +
                        $"action={action} reason={reason}");
                }

                if (failTranslation)
                {
                    error =
                        $"guest-bink-isa-gap shader=0x{_state.Program.Address:X16} " +
                        $"pc=0x{instruction.Pc:X} op={instruction.Opcode}: {reason}";
                    return false;
                }

                if (!legacyZero)
                {
                    return true;
                }
            }

            if (SoftFailTrace)
            {
                var key = $"{_stage}:{instruction.Opcode}";
                if (SoftFailSeen.TryAdd(key, 0))
                {
                    Console.Error.WriteLine(
                        $"[SHADER-SOFT-FAIL] stage={_stage} pc=0x{instruction.Pc:X} " +
                        $"op={instruction.Opcode} reason={reason}");
                }
            }

            foreach (var dest in instruction.Destinations)
            {
                if (dest.Kind == Gen5OperandKind.VectorRegister)
                    StoreV(dest.Value, UInt(0));
                else if (dest.Kind == Gen5OperandKind.ScalarRegister)
                    StoreS(dest.Value, UInt(0));
            }

            return true;
        }
    }
}
