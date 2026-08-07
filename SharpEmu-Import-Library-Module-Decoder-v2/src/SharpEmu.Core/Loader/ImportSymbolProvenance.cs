// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Generic;
using System.Linq;

namespace SharpEmu.Core.Loader;

/// <summary>
/// Retains the complete ELF import symbol and its decoded PS4/PS5 dynamic
/// library/module metadata while the runtime continues to use the compact NID
/// as the lookup key.
/// </summary>
internal static class ImportSymbolProvenance
{
    private static readonly object Gate = new();
    private static readonly Dictionary<string, HashSet<ProvenanceEntry>>
        EntriesByNid = new(StringComparer.Ordinal);

    public static void Reset()
    {
        lock (Gate)
        {
            EntriesByNid.Clear();
        }
    }

    public static void Register(
        string nid,
        string rawSymbolName,
        string? libraryName = null,
        string? moduleName = null,
        ushort libraryVersion = 0,
        byte moduleVersionMajor = 0,
        byte moduleVersionMinor = 0)
    {
        if (string.IsNullOrWhiteSpace(nid) ||
            string.IsNullOrWhiteSpace(rawSymbolName))
        {
            return;
        }

        var entry = new ProvenanceEntry(
            rawSymbolName,
            libraryName ?? string.Empty,
            moduleName ?? string.Empty,
            libraryVersion,
            moduleVersionMajor,
            moduleVersionMinor);

        lock (Gate)
        {
            if (!EntriesByNid.TryGetValue(nid, out var entries))
            {
                entries = [];
                EntriesByNid.Add(nid, entries);
            }

            entries.Add(entry);
        }
    }

    public static bool TryDescribe(string nid, out string description)
    {
        ProvenanceEntry[] entries;
        lock (Gate)
        {
            if (!EntriesByNid.TryGetValue(nid, out var stored) ||
                stored.Count == 0)
            {
                description = string.Empty;
                return false;
            }

            entries = stored
                .OrderByDescending(static value =>
                    !string.IsNullOrWhiteSpace(value.LibraryName) &&
                    !string.IsNullOrWhiteSpace(value.ModuleName))
                .ThenByDescending(static value =>
                    CountSeparators(value.RawSymbolName))
                .ThenByDescending(static value =>
                    value.RawSymbolName.Length)
                .ToArray();
        }

        var entry = entries[0];
        var parts = entry.RawSymbolName.Split('#');
        var libraryToken = parts.Length > 1
            ? parts[1]
            : string.Empty;
        var moduleToken = parts.Length > 2
            ? parts[2]
            : string.Empty;

        description =
            $"symbol='{entry.RawSymbolName}'" +
            (libraryToken.Length == 0
                ? string.Empty
                : $" library_token='{libraryToken}'") +
            (entry.LibraryName.Length == 0
                ? string.Empty
                : $" library='{entry.LibraryName}'") +
            (entry.LibraryVersion == 0
                ? string.Empty
                : $" library_version=0x{entry.LibraryVersion:X4}") +
            (moduleToken.Length == 0
                ? string.Empty
                : $" module_token='{moduleToken}'") +
            (entry.ModuleName.Length == 0
                ? string.Empty
                : $" module='{entry.ModuleName}'") +
            (entry.ModuleVersionMajor == 0 &&
             entry.ModuleVersionMinor == 0
                ? string.Empty
                : $" module_version={entry.ModuleVersionMajor}." +
                  $"{entry.ModuleVersionMinor}") +
            (entries.Length <= 1
                ? string.Empty
                : $" symbol_variants={entries.Length}");
        return true;
    }

    private static int CountSeparators(string value)
    {
        var count = 0;
        foreach (var character in value)
        {
            if (character == '#')
            {
                count++;
            }
        }

        return count;
    }

    private readonly record struct ProvenanceEntry(
        string RawSymbolName,
        string LibraryName,
        string ModuleName,
        ushort LibraryVersion,
        byte ModuleVersionMajor,
        byte ModuleVersionMinor);
}
