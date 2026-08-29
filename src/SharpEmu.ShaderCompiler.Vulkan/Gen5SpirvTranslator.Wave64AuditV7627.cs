// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.7: Wave64/cross-lane census for Bink pixel-truth diagnostics.

using SharpEmu.ShaderCompiler;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static readonly ConcurrentDictionary<ulong, byte>
            _v7627Wave64AuditPrograms = new();

        private void TraceWave64AuditV7627(
            IReadOnlyList<Gen5ShaderInstruction> instructions,
            ulong localInvocationCount,
            uint localSizeX,
            uint localSizeY,
            uint localSizeZ)
        {
            if (_stage != Gen5SpirvStage.Compute ||
                _waveLaneCount != 64 ||
                !string.Equals(
                    Environment.GetEnvironmentVariable("SHARPEMU_WAVE64_AUDIT"),
                    "1",
                    StringComparison.Ordinal) ||
                !_v7627Wave64AuditPrograms.TryAdd(_state.Program.Address, 0))
            {
                return;
            }

            var readlane = 0;
            var writelane = 0;
            var readfirst = 0;
            var permlane16 = 0;
            var permlanex16 = 0;
            var dsPermute = 0;
            var dsBpermute = 0;
            var dpp16 = 0;
            var dpp8 = 0;
            var mbcnt = 0;
            var saveexec = 0;
            var cmpx = 0;

            foreach (var instruction in instructions)
            {
                readlane += instruction.Opcode == "VReadlaneB32" ? 1 : 0;
                writelane += instruction.Opcode == "VWritelaneB32" ? 1 : 0;
                readfirst += instruction.Opcode == "VReadfirstlaneB32" ? 1 : 0;
                permlane16 += instruction.Opcode == "VPermlane16B32" ? 1 : 0;
                permlanex16 += instruction.Opcode == "VPermlanex16B32" ? 1 : 0;
                dsPermute += instruction.Opcode == "DsPermuteB32" ? 1 : 0;
                dsBpermute += instruction.Opcode == "DsBpermuteB32" ? 1 : 0;
                dpp16 += instruction.Control is Gen5DppControl ? 1 : 0;
                dpp8 += instruction.Control is Gen5Dpp8Control ? 1 : 0;
                mbcnt += instruction.Opcode is
                    "VMbcntLoU32B32" or "VMbcntHiU32B32" ? 1 : 0;
                saveexec += instruction.Opcode.Contains(
                    "Saveexec",
                    StringComparison.Ordinal) ? 1 : 0;
                cmpx += instruction.Opcode.StartsWith(
                    "VCmpx",
                    StringComparison.Ordinal) ? 1 : 0;
            }

            var bridge = _multiWave64Bridge
                ? "multi-wave64-rendezvous"
                : _emulateWave64
                    ? _singleWave64ActiveLanesV762414 < 64
                        ? "partial-wave64-workgroup"
                        : "single-wave64-workgroup"
                    : "native-or-unbridged";

            Console.Error.WriteLine(
                "[V76.2.7][WAVE64-AUDIT] " +
                $"shader=0x{_state.Program.Address:X16} " +
                $"local={localSizeX}x{localSizeY}x{localSizeZ} " +
                $"invocations={localInvocationCount} bridge={bridge} " +
                $"instructions={instructions.Count} " +
                $"readlane={readlane} writelane={writelane} readfirst={readfirst} " +
                $"permlane16={permlane16} permlanex16={permlanex16} " +
                $"ds_permute={dsPermute} ds_bpermute={dsBpermute} " +
                $"dpp16={dpp16} dpp8={dpp8} mbcnt={mbcnt} " +
                $"saveexec={saveexec} cmpx={cmpx} " +
                $"uses_lds={(_usesLds ? 1 : 0)} " +
                $"uses_subgroup={(_usesSubgroupOperations ? 1 : 0)}");
        }
    }
}
