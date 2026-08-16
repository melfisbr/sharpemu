// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;

namespace SharpEmu.ShaderCompiler.Vulkan;

/// <summary>
/// Lightweight structural validation for generated SPIR-V. This does not replace
/// spirv-val; it catches truncated streams, invalid instruction word counts,
/// missing module essentials, and invalid ID bounds before Vulkan sees the module.
/// </summary>
internal static class SpirvStructuralValidator
{
    private const uint Magic = 0x07230203;
    private const ushort OpMemoryModel = 14;
    private const ushort OpEntryPoint = 15;
    private const ushort OpFunction = 54;

    public static bool TryValidate(ReadOnlySpan<byte> bytes, out string error)
    {
        error = string.Empty;

        if (bytes.Length < 5 * sizeof(uint) || (bytes.Length & 3) != 0)
        {
            error = $"SPIR-V byte length {bytes.Length} is not a valid word-aligned module.";
            return false;
        }

        var magic = BinaryPrimitives.ReadUInt32LittleEndian(bytes);
        if (magic != Magic)
        {
            error = $"SPIR-V magic is 0x{magic:X8}, expected 0x{Magic:X8}.";
            return false;
        }

        var bound = BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(3 * sizeof(uint)));
        if (bound == 0)
        {
            error = "SPIR-V ID bound is zero.";
            return false;
        }

        var words = bytes.Length / sizeof(uint);
        var cursor = 5;
        var hasMemoryModel = false;
        var hasEntryPoint = false;
        var hasFunction = false;

        while (cursor < words)
        {
            var firstWord = BinaryPrimitives.ReadUInt32LittleEndian(
                bytes.Slice(cursor * sizeof(uint), sizeof(uint)));
            var wordCount = (int)(firstWord >> 16);
            var opcode = (ushort)(firstWord & 0xFFFF);

            if (wordCount <= 0)
            {
                error = $"SPIR-V instruction at word {cursor} has wordCount={wordCount}.";
                return false;
            }

            if (cursor > words - wordCount)
            {
                error =
                    $"SPIR-V instruction opcode={opcode} at word {cursor} overruns " +
                    $"module ({wordCount} words, remaining={words - cursor}).";
                return false;
            }

            hasMemoryModel |= opcode == OpMemoryModel;
            hasEntryPoint |= opcode == OpEntryPoint;
            hasFunction |= opcode == OpFunction;
            cursor += wordCount;
        }

        if (cursor != words)
        {
            error = $"SPIR-V parser ended at word {cursor}, module has {words} words.";
            return false;
        }

        if (!hasMemoryModel || !hasEntryPoint || !hasFunction)
        {
            error =
                $"SPIR-V missing required structure: memory_model={hasMemoryModel} " +
                $"entry_point={hasEntryPoint} function={hasFunction}.";
            return false;
        }

        return true;
    }
}
