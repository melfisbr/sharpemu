// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        // V76.0.10: RDNA2 DS_SWIZZLE_B32 is a register lane-permute operation.
        // It never accesses LDS banks. All four hardware modes operate
        // independently on each 32-lane half of a wave64, which maps directly
        // to the subgroup32 execution model used by this Vulkan backend.
        private bool TryEmitDsSwizzleB32V7610(
            Gen5ShaderInstruction instruction,
            Gen5DataShareControl control,
            out string error)
        {
            error = string.Empty;
            if (instruction.Sources.Count < 1 || instruction.Destinations.Count < 1)
            {
                error = "missing DS_SWIZZLE_B32 operand";
                return false;
            }

            var source = GetRawSource(instruction, 0);
            var lane = BitwiseAnd(GuestWaveLane(), UInt(31));
            var pattern = ((control.Offset1 & 0xFFu) << 8) | (control.Offset0 & 0xFFu);
            uint targetLane;

            if (pattern >= 0xE000u)
            {
                // FFT mode from the RDNA2 ISA:
                //   j = reverse_bits(i[4:0]) >> popcount(mask)
                //   j |= i & mask
                var mask = pattern & 0x1Fu;
                var reversed = _module.AddInstruction(
                    SpirvOp.BitReverse,
                    _uintType,
                    lane);
                var reversed5 = ShiftRightLogical(reversed, UInt(27));
                var shift = PopCount5V7610(mask);
                var compacted = shift == 0
                    ? reversed5
                    : ShiftRightLogical(reversed5, UInt(shift));
                targetLane = BitwiseAnd(
                    BitwiseOr(compacted, BitwiseAnd(lane, UInt(mask))),
                    UInt(31));
            }
            else if (pattern >= 0xC000u)
            {
                // Rotate mode from the RDNA2 ISA. The mask preserves selected
                // lane-id bits while the remaining bits come from the rotated
                // lane. Direction=1 means a negative (right) rotation.
                var mask = pattern & 0x1Fu;
                var rotate = (pattern >> 5) & 0x1Fu;
                var rotateRight = ((pattern >> 10) & 1u) != 0;
                var delta = rotateRight
                    ? ((32u - rotate) & 0x1Fu)
                    : rotate;
                var rotated = BitwiseAnd(IAdd(lane, UInt(delta)), UInt(31));
                targetLane = BitwiseAnd(
                    BitwiseOr(
                        BitwiseAnd(lane, UInt(mask)),
                        BitwiseAnd(rotated, UInt((~mask) & 0x1Fu))),
                    UInt(31));
            }
            else if ((pattern & 0x8000u) != 0)
            {
                // Quad-permute mode. The low eight pattern bits select one of
                // the four source lanes independently for each destination in
                // every consecutive group of four lanes.
                var laneInQuad = BitwiseAnd(lane, UInt(3));
                var selector = UInt(pattern & 3u);
                for (var index = 1u; index < 4; index++)
                {
                    selector = _module.AddInstruction(
                        SpirvOp.Select,
                        _uintType,
                        _module.AddInstruction(
                            SpirvOp.IEqual,
                            _boolType,
                            laneInQuad,
                            UInt(index)),
                        UInt((pattern >> checked((int)(index * 2))) & 3u),
                        selector);
                }

                targetLane = IAdd(BitwiseAnd(lane, UInt(0xFFFF_FFFCu)), selector);
            }
            else
            {
                // Bitmask mode, applied independently to each 32-lane half:
                //   j = ((i & and_mask) | or_mask) ^ xor_mask
                var andMask = pattern & 0x1Fu;
                var orMask = (pattern >> 5) & 0x1Fu;
                var xorMask = (pattern >> 10) & 0x1Fu;
                targetLane = BitwiseAnd(
                    BitwiseXor(
                        BitwiseOr(
                            BitwiseAnd(lane, UInt(andMask)),
                            UInt(orMask)),
                        UInt(xorMask)),
                    UInt(31));
            }

            var shuffled = _module.AddInstruction(
                SpirvOp.GroupNonUniformShuffle,
                _uintType,
                UInt(3),
                source,
                targetLane);

            // DS lane-permute reads from inactive source lanes as zero while an
            // inactive destination lane keeps its old VGPR value. Host Vulkan
            // invocations remain live; guest EXEC is modeled explicitly, so a
            // shuffled EXEC word reproduces RDNA thread_valid[] semantics.
            var activeWord = _module.AddInstruction(
                SpirvOp.Select,
                _uintType,
                Load(_boolType, _exec),
                UInt(1),
                UInt(0));
            var sourceActive = IsNotZero(
                _module.AddInstruction(
                    SpirvOp.GroupNonUniformShuffle,
                    _uintType,
                    UInt(3),
                    activeWord,
                    targetLane));
            var result = _module.AddInstruction(
                SpirvOp.Select,
                _uintType,
                sourceActive,
                shuffled,
                UInt(0));

            StoreV(instruction.Destinations[0].Value, result);
            return true;
        }

        private static uint PopCount5V7610(uint value)
        {
            value &= 0x1Fu;
            uint count = 0;
            while (value != 0)
            {
                count += value & 1u;
                value >>= 1;
            }

            return count;
        }
    }
}
