// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Generic;
using System.Linq;
using SharpEmu.HLE;

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
        ProvenanceEntry[] targetEntries;
        KeyValuePair<string, ProvenanceEntry[]>[] allEntries;

        lock (Gate)
        {
            if (!EntriesByNid.TryGetValue(nid, out var stored) ||
                stored.Count == 0)
            {
                description = string.Empty;
                return false;
            }

            targetEntries = stored
                .OrderByDescending(static value =>
                    !string.IsNullOrWhiteSpace(value.LibraryName) &&
                    !string.IsNullOrWhiteSpace(value.ModuleName))
                .ThenByDescending(static value =>
                    CountSeparators(value.RawSymbolName))
                .ThenByDescending(static value =>
                    value.RawSymbolName.Length)
                .ToArray();

            allEntries = EntriesByNid
                .Select(static pair =>
                    new KeyValuePair<string, ProvenanceEntry[]>(
                        pair.Key,
                        pair.Value.ToArray()))
                .ToArray();
        }

        var entry = targetEntries[0];
        var parts = entry.RawSymbolName.Split('#');
        var libraryToken = parts.Length > 1
            ? parts[1]
            : string.Empty;
        var moduleToken = parts.Length > 2
            ? parts[2]
            : string.Empty;

        var knownPeers = new List<string>();
        var matchingTokenNids = 0;
        foreach (var pair in allEntries)
        {
            if (string.Equals(pair.Key, nid, StringComparison.Ordinal))
            {
                continue;
            }

            var matchesTokens = false;
            foreach (var peerEntry in pair.Value)
            {
                var peerParts = peerEntry.RawSymbolName.Split('#');
                if (peerParts.Length >= 3 &&
                    string.Equals(
                        peerParts[1],
                        libraryToken,
                        StringComparison.Ordinal) &&
                    string.Equals(
                        peerParts[2],
                        moduleToken,
                        StringComparison.Ordinal))
                {
                    matchesTokens = true;
                    break;
                }
            }

            if (!matchesTokens)
            {
                continue;
            }

            matchingTokenNids++;
            if (Aerolib.Instance.TryGetName(pair.Key, out var knownName))
            {
                knownPeers.Add($"{pair.Key}={knownName}");
            }
        }

        knownPeers.Sort(StringComparer.Ordinal);
        const int maxPeerNames = 16;
        var displayedPeers = knownPeers.Count <= maxPeerNames
            ? knownPeers
            : knownPeers.Take(maxPeerNames).ToList();

        description =
            $"symbol='{entry.RawSymbolName}'" +
            (libraryToken.Length == 0
                ? string.Empty
                : $" library_token='{libraryToken}'") +
            (libraryToken.Length != 0 && entry.LibraryName.Length == 0
                ? " library='<unmapped>'"
                : entry.LibraryName.Length == 0
                    ? string.Empty
                    : $" library='{entry.LibraryName}'") +
            (entry.LibraryVersion == 0
                ? string.Empty
                : $" library_version=0x{entry.LibraryVersion:X4}") +
            (moduleToken.Length == 0
                ? string.Empty
                : $" module_token='{moduleToken}'") +
            (moduleToken.Length != 0 && entry.ModuleName.Length == 0
                ? " module='<unmapped>'"
                : entry.ModuleName.Length == 0
                    ? string.Empty
                    : $" module='{entry.ModuleName}'") +
            (entry.ModuleVersionMajor == 0 &&
             entry.ModuleVersionMinor == 0
                ? string.Empty
                : $" module_version={entry.ModuleVersionMajor}." +
                  $"{entry.ModuleVersionMinor}") +
            (targetEntries.Length <= 1
                ? string.Empty
                : $" symbol_variants={targetEntries.Length}") +
            $" token_peer_nids={matchingTokenNids}" +
            $" known_token_peers={knownPeers.Count}" +
            (displayedPeers.Count == 0
                ? string.Empty
                : $" peer_names='{string.Join(";", displayedPeers)}'") +
            (knownPeers.Count <= maxPeerNames
                ? string.Empty
                : $" peer_names_truncated={knownPeers.Count - maxPeerNames}");
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
