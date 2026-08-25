// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Text;

namespace SharpEmu.Core.Loader;

/// <summary>
/// Decodes PS5 SCE dynamic import metadata observed in Gen5 SceDynExec/SceDynamic images.
/// The decoder is intentionally format-generic: no title names or NIDs are hard-coded.
/// </summary>
internal static class Ps5SceDynamicImportMetadata
{
    // Observed directly in PS5 PT_DYNAMIC tables.
    internal const ulong NeededModuleTag = 0x61000045UL;
    internal const ulong ImportLibraryTag = 0x61000049UL;

    internal const string TokenAlphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-";

    internal enum NameKind
    {
        Module,
        Library,
    }

    internal readonly record struct NameRecord(
        NameKind Kind,
        int Id,
        char Token,
        uint NameOffset,
        ushort Metadata,
        ulong RawValue,
        string Name);

    internal readonly record struct SymbolIdentity(
        string Nid,
        char LibraryToken,
        int LibraryId,
        char ModuleToken,
        int ModuleId);

    internal static bool TryDecodeNameRecord(
        ulong tag,
        ulong value,
        ReadOnlySpan<byte> stringTable,
        out NameRecord record)
    {
        NameKind kind;
        if (tag == NeededModuleTag)
        {
            kind = NameKind.Module;
        }
        else if (tag == ImportLibraryTag)
        {
            kind = NameKind.Library;
        }
        else
        {
            record = default;
            return false;
        }

        var id = checked((int)((value >> 48) & 0xFFFFUL));
        var nameOffset = unchecked((uint)value);
        var metadata = unchecked((ushort)((value >> 32) & 0xFFFFUL));

        if ((uint)id >= (uint)TokenAlphabet.Length ||
            nameOffset >= (uint)stringTable.Length ||
            !TryReadCString(stringTable, nameOffset, out var name))
        {
            record = default;
            return false;
        }

        record = new NameRecord(
            kind,
            id,
            TokenAlphabet[id],
            nameOffset,
            metadata,
            value,
            name);
        return true;
    }

    internal static bool TryDecodeSymbolIdentity(
        ReadOnlySpan<char> symbolName,
        out SymbolIdentity identity)
    {
        var firstHash = symbolName.IndexOf('#');
        if (firstHash <= 0 || firstHash + 2 >= symbolName.Length)
        {
            identity = default;
            return false;
        }

        var remainder = symbolName[(firstHash + 1)..];
        var secondRelativeHash = remainder.IndexOf('#');
        if (secondRelativeHash != 1 || secondRelativeHash + 2 != remainder.Length)
        {
            identity = default;
            return false;
        }

        var libraryToken = remainder[0];
        var moduleToken = remainder[2];
        var libraryId = TokenAlphabet.IndexOf(libraryToken);
        var moduleId = TokenAlphabet.IndexOf(moduleToken);
        if (libraryId < 0 || moduleId < 0)
        {
            identity = default;
            return false;
        }

        identity = new SymbolIdentity(
            symbolName[..firstHash].ToString(),
            libraryToken,
            libraryId,
            moduleToken,
            moduleId);
        return true;
    }

    private static bool TryReadCString(
        ReadOnlySpan<byte> stringTable,
        uint offset,
        out string value)
    {
        if (offset >= (uint)stringTable.Length)
        {
            value = string.Empty;
            return false;
        }

        var slice = stringTable[(int)offset..];
        var terminator = slice.IndexOf((byte)0);
        if (terminator < 0)
        {
            value = string.Empty;
            return false;
        }

        value = Encoding.UTF8.GetString(slice[..terminator]);
        return value.Length != 0;
    }
}
