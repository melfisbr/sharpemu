// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace SharpEmu.Libs.Kernel;

public static partial class KernelMemoryCompatExports
{
    // SHARPEMU_DBFZ_UE_CONTENT_DISCOVERY_V1_7_1_2_1
    //
    // Two compatibility gaps are handled here:
    //
    // 1) Directory discovery must not fail merely because one child entry is
    //    inaccessible to the Windows host. Unreal uses directory enumeration
    //    to discover cooked container files.
    //
    // 2) Some dumps stage GlobalShaderCache-SF_PS5.bin outside the exact
    //    /app0/Engine spelling expected by the shipping executable. If a loose
    //    file with the exact basename exists elsewhere under app0, resolve that
    //    file instead of reporting a false absence.
    //
    // No synthetic shader-cache bytes are generated. If the cache is genuinely
    // absent as a loose file, the normal path remains absent so archive/content
    // discovery can be diagnosed honestly.

    private const string DbfzGlobalShaderCacheBasename =
        "globalshadercache-sf_ps5.bin";

    private static readonly object _dbfzContentDiscoveryGate = new();
    private static string? _dbfzGlobalShaderCacheLooseFallback;
    private static int _dbfzGlobalShaderCacheLooseScanComplete;

    private static string[] EnumerateDirectoryEntriesForContentDiscovery(
        string hostPath)
    {
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = false,
            IgnoreInaccessible = true,
            ReturnSpecialDirectories = false,
            AttributesToSkip = 0
        };

        string[] children;
        try
        {
            children = Directory
                .EnumerateFileSystemEntries(hostPath, "*", options)
                .Select(Path.GetFileName)
                .Where(static name => !string.IsNullOrEmpty(name))
                .OrderBy(static name => name, StringComparer.OrdinalIgnoreCase)
                .Select(static name => name!)
                .ToArray();
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException)
        {
            // Preserve a valid directory fd even if host enumeration itself is
            // partially unavailable. "." / ".." are required guest entries.
            Console.Error.WriteLine(
                "[LOADER][WARN] dbfz.content_directory enumeration-fallback " +
                $"host='{hostPath}' ex={ex.GetType().Name}");
            children = Array.Empty<string>();
        }

        var entries = new string[children.Length + 2];
        entries[0] = ".";
        entries[1] = "..";
        Array.Copy(children, 0, entries, 2, children.Length);

        Console.Error.WriteLine(
            "[LOADER][TRACE] dbfz.content_directory enumerated " +
            $"host='{hostPath}' children={children.Length} entries={entries.Length}");

        return entries;
    }

    private static string ResolveDbfzLooseGlobalShaderCacheAlias(
        string guestPath,
        string resolvedHostPath)
    {
        if (string.IsNullOrWhiteSpace(guestPath) ||
            !guestPath.EndsWith(
                "/" + DbfzGlobalShaderCacheBasename,
                StringComparison.OrdinalIgnoreCase))
        {
            return resolvedHostPath;
        }

        if (!string.IsNullOrEmpty(resolvedHostPath) &&
            File.Exists(resolvedHostPath))
        {
            return resolvedHostPath;
        }

        var cached = Volatile.Read(
            ref _dbfzGlobalShaderCacheLooseFallback);
        if (!string.IsNullOrWhiteSpace(cached) &&
            File.Exists(cached))
        {
            return cached;
        }

        if (Volatile.Read(
                ref _dbfzGlobalShaderCacheLooseScanComplete) != 0)
        {
            return resolvedHostPath;
        }

        lock (_dbfzContentDiscoveryGate)
        {
            cached = _dbfzGlobalShaderCacheLooseFallback;
            if (!string.IsNullOrWhiteSpace(cached) &&
                File.Exists(cached))
            {
                return cached;
            }

            if (_dbfzGlobalShaderCacheLooseScanComplete != 0)
            {
                return resolvedHostPath;
            }

            var app0Root = ResolveApp0Root();
            if (!string.IsNullOrWhiteSpace(app0Root) &&
                Directory.Exists(app0Root))
            {
                var options = new EnumerationOptions
                {
                    RecurseSubdirectories = true,
                    IgnoreInaccessible = true,
                    ReturnSpecialDirectories = false,
                    AttributesToSkip = 0
                };

                try
                {
                    foreach (var file in Directory.EnumerateFiles(
                        app0Root,
                        "*",
                        options))
                    {
                        if (!string.Equals(
                                Path.GetFileName(file),
                                DbfzGlobalShaderCacheBasename,
                                StringComparison.OrdinalIgnoreCase))
                        {
                            continue;
                        }

                        _dbfzGlobalShaderCacheLooseFallback =
                            Path.GetFullPath(file);

                        Console.Error.WriteLine(
                            "[LOADER][WARN] dbfz.global_shader_cache_alias " +
                            $"guest='{guestPath}' requested='{resolvedHostPath}' " +
                            $"resolved='{_dbfzGlobalShaderCacheLooseFallback}'");

                        break;
                    }
                }
                catch (Exception ex) when (
                    ex is IOException or UnauthorizedAccessException or
                    ArgumentException or NotSupportedException)
                {
                    Console.Error.WriteLine(
                        "[LOADER][WARN] dbfz.global_shader_cache_scan_failed " +
                        $"root='{app0Root}' ex={ex.GetType().Name}");
                }
            }

            Volatile.Write(
                ref _dbfzGlobalShaderCacheLooseScanComplete,
                1);

            return !string.IsNullOrWhiteSpace(
                    _dbfzGlobalShaderCacheLooseFallback)
                ? _dbfzGlobalShaderCacheLooseFallback
                : resolvedHostPath;
        }
    }
}
