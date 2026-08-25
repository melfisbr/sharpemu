// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Linq;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private enum RdnaAtomicSpaceV7609
        {
            Workgroup,
            StorageBuffer,
            Image,
        }

        private uint _rdnaIncWorkgroupV7609;
        private uint _rdnaDecWorkgroupV7609;
        private uint _rdnaIncStorageV7609;
        private uint _rdnaDecStorageV7609;
        private uint _rdnaIncImageUintV7609;
        private uint _rdnaDecImageUintV7609;
        private uint _rdnaIncImageSintV7609;
        private uint _rdnaDecImageSintV7609;

        // V76.0.9: RDNA INC/DEC are bounded read-modify-write operations, not
        // plain SPIR-V increment/decrement. Declare compact CAS-loop helpers
        // before main() so every memory space preserves the DATA clamp operand.
        private void DeclareRdnaAtomicCompatV7609()
        {
            var instructions = _state.Program.Instructions;
            var usesDsIncDec = instructions.Any(static instruction =>
                instruction.Opcode is
                    "DsIncU32" or "DsIncRtnU32" or
                    "DsDecU32" or "DsDecRtnU32");
            var usesStorageIncDec = instructions.Any(static instruction =>
                instruction.Opcode is
                    "BufferAtomicInc" or "BufferAtomicDec" or
                    "GlobalAtomicInc" or "GlobalAtomicDec" or
                    "FlatAtomicInc" or "FlatAtomicDec");
            var usesImageIncDec = instructions.Any(static instruction =>
                instruction.Opcode is "ImageAtomicInc" or "ImageAtomicDec");

            if (usesDsIncDec &&
                _stage == Gen5SpirvStage.Compute &&
                _ldsElementPointer != 0)
            {
                _rdnaIncWorkgroupV7609 = DeclareRdnaBoundedAtomicV7609(
                    _ldsElementPointer,
                    _uintType,
                    scope: 2,
                    semantics: 0x108,
                    decrement: false,
                    "rdna_atomic_inc_workgroup_v7609");
                _rdnaDecWorkgroupV7609 = DeclareRdnaBoundedAtomicV7609(
                    _ldsElementPointer,
                    _uintType,
                    scope: 2,
                    semantics: 0x108,
                    decrement: true,
                    "rdna_atomic_dec_workgroup_v7609");
            }

            if (usesStorageIncDec && _storageUintPointer != 0)
            {
                _rdnaIncStorageV7609 = DeclareRdnaBoundedAtomicV7609(
                    _storageUintPointer,
                    _uintType,
                    scope: 1,
                    semantics: 0x48,
                    decrement: false,
                    "rdna_atomic_inc_storage_v7609");
                _rdnaDecStorageV7609 = DeclareRdnaBoundedAtomicV7609(
                    _storageUintPointer,
                    _uintType,
                    scope: 1,
                    semantics: 0x48,
                    decrement: true,
                    "rdna_atomic_dec_storage_v7609");
            }

            if (usesImageIncDec)
            {
                var imageUintPointer = _module.TypePointer(
                    SpirvStorageClass.Image,
                    _uintType);
                var imageSintPointer = _module.TypePointer(
                    SpirvStorageClass.Image,
                    _intType);
                _rdnaIncImageUintV7609 = DeclareRdnaBoundedAtomicV7609(
                    imageUintPointer,
                    _uintType,
                    scope: 1,
                    semantics: 0x808,
                    decrement: false,
                    "rdna_atomic_inc_image_u32_v7609");
                _rdnaDecImageUintV7609 = DeclareRdnaBoundedAtomicV7609(
                    imageUintPointer,
                    _uintType,
                    scope: 1,
                    semantics: 0x808,
                    decrement: true,
                    "rdna_atomic_dec_image_u32_v7609");
                _rdnaIncImageSintV7609 = DeclareRdnaBoundedAtomicV7609(
                    imageSintPointer,
                    _intType,
                    scope: 1,
                    semantics: 0x808,
                    decrement: false,
                    "rdna_atomic_inc_image_i32_v7609");
                _rdnaDecImageSintV7609 = DeclareRdnaBoundedAtomicV7609(
                    imageSintPointer,
                    _intType,
                    scope: 1,
                    semantics: 0x808,
                    decrement: true,
                    "rdna_atomic_dec_image_i32_v7609");
            }
        }

        private uint DeclareRdnaBoundedAtomicV7609(
            uint pointerType,
            uint valueType,
            uint scope,
            uint semantics,
            bool decrement,
            string name)
        {
            var functionType = _module.TypeFunction(
                valueType,
                pointerType,
                valueType);
            var function = _module.BeginFunction(valueType, functionType);
            _module.AddName(function, name);
            var pointer = _module.AddFunctionParameter(pointerType);
            var clamp = _module.AddFunctionParameter(valueType);
            _module.AddLabel();

            // Function-scope variables must be declared in the entry block.
            var functionValuePointer = _module.TypePointer(
                SpirvStorageClass.Function,
                valueType);
            var expectedVariable = _module.AddFunctionVariable(functionValuePointer);
            var zero = valueType == _uintType
                ? UInt(0)
                : _module.Constant(_intType, 0);
            var one = valueType == _uintType
                ? UInt(1)
                : _module.Constant(_intType, 1);

            // Atomic add of zero is an atomic load on the same location while
            // remaining valid on the SPIR-V subset already used by SharpEmu.
            var initial = _module.AddInstruction(
                SpirvOp.AtomicIAdd,
                valueType,
                pointer,
                UInt(scope),
                UInt(semantics),
                zero);
            Store(expectedVariable, initial);

            var loopHeader = _module.AllocateId();
            var loopContinue = _module.AllocateId();
            var loopMerge = _module.AllocateId();
            _module.AddStatement(SpirvOp.Branch, loopHeader);
            _module.AddLabel(loopHeader);
            _module.AddStatement(
                SpirvOp.LoopMerge,
                loopMerge,
                loopContinue,
                0);

            var current = Load(valueType, expectedVariable);
            uint desired;
            if (decrement)
            {
                var isZero = _module.AddInstruction(
                    SpirvOp.IEqual,
                    _boolType,
                    current,
                    zero);
                var aboveClamp = _module.AddInstruction(
                    SpirvOp.UGreaterThan,
                    _boolType,
                    current,
                    clamp);
                var wrap = _module.AddInstruction(
                    SpirvOp.LogicalOr,
                    _boolType,
                    isZero,
                    aboveClamp);
                var decremented = _module.AddInstruction(
                    SpirvOp.ISub,
                    valueType,
                    current,
                    one);
                desired = _module.AddInstruction(
                    SpirvOp.Select,
                    valueType,
                    wrap,
                    clamp,
                    decremented);
            }
            else
            {
                var wrap = _module.AddInstruction(
                    SpirvOp.UGreaterThanEqual,
                    _boolType,
                    current,
                    clamp);
                var incremented = _module.AddInstruction(
                    SpirvOp.IAdd,
                    valueType,
                    current,
                    one);
                desired = _module.AddInstruction(
                    SpirvOp.Select,
                    valueType,
                    wrap,
                    zero,
                    incremented);
            }

            // AtomicCompareExchange returns the value observed before the
            // exchange. Retry with that value until our comparison succeeds.
            var unequalSemantics = (semantics & ~0x8u) | 0x2u;
            var observed = _module.AddInstruction(
                SpirvOp.AtomicCompareExchange,
                valueType,
                pointer,
                UInt(scope),
                UInt(semantics),
                UInt(unequalSemantics),
                desired,
                current);
            var succeeded = _module.AddInstruction(
                SpirvOp.IEqual,
                _boolType,
                observed,
                current);
            _module.AddStatement(
                SpirvOp.BranchConditional,
                succeeded,
                loopMerge,
                loopContinue);

            _module.AddLabel(loopContinue);
            Store(expectedVariable, observed);
            _module.AddStatement(SpirvOp.Branch, loopHeader);

            _module.AddLabel(loopMerge);
            _module.AddStatement(SpirvOp.ReturnValue, current);
            _module.EndFunction();
            return function;
        }

        private uint EmitRdnaBoundedAtomicV7609(
            SpirvOp op,
            uint type,
            uint pointer,
            uint clamp,
            RdnaAtomicSpaceV7609 space)
        {
            var decrement = op == SpirvOp.AtomicIDecrement;
            uint function = space switch
            {
                RdnaAtomicSpaceV7609.Workgroup => decrement
                    ? _rdnaDecWorkgroupV7609
                    : _rdnaIncWorkgroupV7609,
                RdnaAtomicSpaceV7609.StorageBuffer => decrement
                    ? _rdnaDecStorageV7609
                    : _rdnaIncStorageV7609,
                RdnaAtomicSpaceV7609.Image when type == _intType => decrement
                    ? _rdnaDecImageSintV7609
                    : _rdnaIncImageSintV7609,
                RdnaAtomicSpaceV7609.Image => decrement
                    ? _rdnaDecImageUintV7609
                    : _rdnaIncImageUintV7609,
                _ => 0,
            };
            if (function == 0)
            {
                throw new InvalidOperationException(
                    $"V76.0.9 atomic helper missing space={space} type={type} op={op}");
            }

            return _module.AddInstruction(
                SpirvOp.FunctionCall,
                type,
                function,
                pointer,
                clamp);
        }
    }
}
