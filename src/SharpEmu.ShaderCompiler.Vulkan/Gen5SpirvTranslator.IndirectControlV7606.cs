// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        // V76.0.6.1: SOP1 indirect control-flow is uniform for the whole wave.
        // Keep it inside the existing PC dispatcher instead of lowering it to
        // unstructured SPIR-V branches. S_SETPC_B64 consumes an absolute byte
        // address. S_SWAPPC_B64 additionally writes the return byte address to
        // its destination SGPR pair.
        private static bool IsIndirectPcTransferV7606(string opcode) =>
            opcode is "SSetpcB64" or "SSwappcB64";

        private bool TryEmitIndirectPcTransferV7606(
            IReadOnlyList<ShaderBlock> blocks,
            Gen5ShaderInstruction instruction,
            out string error)
        {
            error = string.Empty;
            if (instruction.Sources.Count == 0)
            {
                error = $"missing indirect PC source for {instruction.Opcode}";
                return false;
            }

            // Read S0 before writing S_SWAPPC's destination. Source and
            // destination are allowed to overlap; the jump must use the
            // pre-instruction SGPR value.
            var targetAddress = BitwiseAnd64(
                GetRawSource64(instruction, 0),
                _module.Constant64(_ulongType, 0xFFFF_FFFF_FFFF_FFFCUL));

            if (instruction.Opcode == "SSwappcB64")
            {
                if (instruction.Destinations.Count != 1 ||
                    instruction.Destinations[0] is not
                    {
                        Kind: Gen5OperandKind.ScalarRegister,
                    } destination ||
                    destination.Value >= ScalarRegisterCount - 1)
                {
                    error = "S_SWAPPC_B64 requires a writable SGPR pair destination";
                    return false;
                }

                var returnAddress = _state.Program.Address +
                    instruction.Pc +
                    (ulong)(instruction.Words.Count * sizeof(uint));
                StoreS64(
                    destination.Value,
                    _module.Constant64(_ulongType, returnAddress));
            }

            // RDNA forces the low two bits of PC to zero because PC is a
            // DWORD-aligned byte address. Compare against every legal basic
            // block address. BuildBasicBlocks() deliberately makes every
            // instruction a leader only for programs that contain an indirect
            // PC transfer, so any decoded call/return target is representable.
            var selectedBlock = UInt(uint.MaxValue);
            for (var index = 0; index < blocks.Count; index++)
            {
                var blockAddress = _state.Program.Address + blocks[index].StartPc;
                var matches = _module.AddInstruction(
                    SpirvOp.IEqual,
                    _boolType,
                    targetAddress,
                    _module.Constant64(_ulongType, blockAddress));
                selectedBlock = _module.AddInstruction(
                    SpirvOp.Select,
                    _uintType,
                    matches,
                    UInt((uint)index),
                    selectedBlock);
            }

            // An out-of-program target deliberately selects uint.MaxValue.
            // The existing dispatcher default case then deactivates the
            // invocation instead of wedging the host GPU in an invalid loop.
            Store(_programCounter, selectedBlock);
            return true;
        }
    }
}
