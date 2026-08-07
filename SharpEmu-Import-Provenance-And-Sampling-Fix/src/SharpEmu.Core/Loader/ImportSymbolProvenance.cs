// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Generic;
using System.Linq;

namespace SharpEmu.Core.Loader;

/// <summary>
/// Retains the complete ELF import symbol while the runtime continues to use
/// the compact NID as its lookup key. PS4/PS5 import names can contain suffix
/// tokens after '#'; discarding them made an unknown NID impossible to assign
/// to its source library/module.
/// </summary>
internal static class ImportSymbolProvenance
{
    private static readonly object Gate = new();
    private static readonly Dictionary<string, HashSet<string>> RawSymbolsByNid =
        new(StringComparer.Ordinal);

    public static void Reset()
    {
        lock (Gate)
        {
            RawSymbolsByNid.Clear();
        }
    }

    public static void Register(string nid, string rawSymbolName)
    {
        if (string.IsNullOrWhiteSpace(nid) ||
            string.IsNullOrWhiteSpace(rawSymbolName))
        {
            return;
        }

        lock (Gate)
        {
            if (!RawSymbolsByNid.TryGetValue(nid, out var symbols))
            {
                symbols = new HashSet<string>(StringComparer.Ordinal);
                RawSymbolsByNid.Add(nid, symbols);
            }

            symbols.Add(rawSymbolName);
        }
    }

    public static bool TryDescribe(string nid, out string description)
    {
        string[] symbols;
        lock (Gate)
        {
            if (!RawSymbolsByNid.TryGetValue(nid, out var stored) ||
                stored.Count == 0)
            {
                description = string.Empty;
                return false;
            }

            symbols = stored
                .OrderByDescending(static value => CountSeparators(value))
                .ThenByDescending(static value => value.Length)
                .ToArray();
        }

        var raw = symbols[0];
        var parts = raw.Split('#');
        var libraryToken = parts.Length > 1 ? parts[1] : string.Empty;
        var moduleToken = parts.Length > 2 ? parts[2] : string.Empty;

        description =
            $"symbol='{raw}'" +
            (libraryToken.Length == 0
                ? string.Empty
                : $" library_token='{libraryToken}'") +
            (moduleToken.Length == 0
                ? string.Empty
                : $" module_token='{moduleToken}'") +
            (symbols.Length <= 1
                ? string.Empty
                : $" symbol_variants={symbols.Length}");
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
}
