// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.25: RDNA2 DS_PERMUTE_B32 / DS_BPERMUTE_B32.

using SharpEmu.ShaderCompiler;
using System.Collections.Concurrent;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static readonly ConcurrentDictionary<ulong, byte>
            _v7625DsPermuteTracedShaders = new();

        private bool TryEmitDsPermuteB32V7625(
            Gen5ShaderInstruction instruction,
            Gen5DataShareControl control,
            out string error)
        {
            error = string.Empty;
            if (_subgroupInvocationIdInput == 0 ||
                instruction.Sources.Count < 2 ||
                instruction.Destinations.Count < 1)
            {
                error = $"{instruction.Opcode} requires subgroup lane, ADDR, DATA0 and VDST";
                return false;
            }

            // RDNA2: index is byte-addressed, the DS immediate is added first,
            // and only bits [6:2] select one of 32 lanes in the same half-wave.
            var offsetBytes = control.Offset0 | (control.Offset1 << 8);
            var indexBytes = IAdd(GetRawSource(instruction, 0), UInt(offsetBytes));
            var routedLane = BitwiseAnd(
                ShiftRightLogical(indexBytes, UInt(2)),
                UInt(31));
            var sourceData = GetRawSource(instruction, 1);

            // Keep routing inside the native subgroup's current 32-lane half.
            // subgroup32: base=0 for each PS5 half-wave; subgroup64: base=0/32.
            var hostLane = Load(_uintType, _subgroupInvocationIdInput);
            var halfBase = BitwiseAnd(hostLane, UInt(0xFFFF_FFE0));
            var activeWord = _module.AddInstruction(
                SpirvOp.Select,
                _uintType,
                Load(_boolType, _exec),
                UInt(1),
                UInt(0));

            uint result;
            if (instruction.Opcode == "DsBpermuteB32")
            {
                // Pull/gather: dst[lane] = src[index[lane]]. Reading from a
                // disabled source lane returns zero. StoreV honors dst EXEC.
                var sourceHostLane = IAdd(halfBase, routedLane);
                var gathered = _module.AddInstruction(
                    SpirvOp.GroupNonUniformShuffle,
                    _uintType,
                    UInt(3),
                    sourceData,
                    sourceHostLane);
                var sourceActive = IsNotZero(
                    _module.AddInstruction(
                        SpirvOp.GroupNonUniformShuffle,
                        _uintType,
                        UInt(3),
                        activeWord,
                        sourceHostLane));
                result = _module.AddInstruction(
                    SpirvOp.Select,
                    _uintType,
                    sourceActive,
                    gathered,
                    UInt(0));
            }
            else
            {
                // Push/scatter: src[lane] writes dst[index[lane]]. Invert the
                // mapping by probing the 32 possible sources. AMD leaves write
                // collisions nondeterministic; selecting the highest active
                // matching lane is deterministic and within the ISA contract.
                var destinationLane = BitwiseAnd(hostLane, UInt(31));
                result = UInt(0);
                for (var sourceLane = 0u; sourceLane < 32; sourceLane++)
                {
                    var sourceHostLane = IAdd(halfBase, UInt(sourceLane));
                    var sourceTarget = _module.AddInstruction(
                        SpirvOp.GroupNonUniformShuffle,
                        _uintType,
                        UInt(3),
                        routedLane,
                        sourceHostLane);
                    var candidate = _module.AddInstruction(
                        SpirvOp.GroupNonUniformShuffle,
                        _uintType,
                        UInt(3),
                        sourceData,
                        sourceHostLane);
                    var sourceActive = IsNotZero(
                        _module.AddInstruction(
                            SpirvOp.GroupNonUniformShuffle,
                            _uintType,
                            UInt(3),
                            activeWord,
                            sourceHostLane));
                    var hitsDestination = _module.AddInstruction(
                        SpirvOp.IEqual,
                        _boolType,
                        sourceTarget,
                        destinationLane);
                    var validWriter = _module.AddInstruction(
                        SpirvOp.LogicalAnd,
                        _boolType,
                        sourceActive,
                        hitsDestination);
                    result = _module.AddInstruction(
                        SpirvOp.Select,
                        _uintType,
                        validWriter,
                        candidate,
                        result);
                }
            }

            StoreV(instruction.Destinations[0].Value, result);

            if (_v7625DsPermuteTracedShaders.TryAdd(_state.Program.Address, 0))
            {
                Console.Error.WriteLine(
                    "[V76.0.25][RDNA2-DS-PERMUTE] " +
                    $"shader=0x{_state.Program.Address:X16} opcode={instruction.Opcode} " +
                    $"offset=0x{offsetBytes:X4} semantics=half-wave32 exec-aware");
            }

            return true;
        }
    }
}
