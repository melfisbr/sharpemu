// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.IO;
using System.Threading;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Kernel;

public static partial class KernelMemoryCompatExports
{
    // SHARPEMU_DBFZ_UE_PAK_DIRECTORY_OPEN_V1_7_2_1_1
    //
    // Directory opens must be resolved before HostMovieBridge/Bink takeover.
    // V1.7.1.2 proved that /app0/red/content/paks exists on the host yet
    // _open(O_DIRECTORY) escaped through the generic UnauthorizedAccess catch
    // without ever reaching EnumerateDirectoryEntriesForContentDiscovery.
    //
    // This helper is called immediately after access/mode resolution and before
    // the movie bridge. It fully handles directories and returns false for
    // ordinary files, leaving the original file path untouched.
    private static bool TryOpenDirectoryBeforeMovieBridge(
        CpuContext ctx,
        string guestPath,
        string hostPath,
        int flags,
        FileAccess access,
        out int result)
    {
        result = 0;

        var wantsDirectory = (flags & O_DIRECTORY) != 0;
        var hostIsDirectory = Directory.Exists(hostPath);

        if (!wantsDirectory && !hostIsDirectory)
        {
            return false;
        }

        if (!hostIsDirectory)
        {
            LogOpenTrace(
                $"_open early-dir-miss path='{guestPath}' host='{hostPath}' flags=0x{flags:X8}");
            result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;
            return true;
        }

        if (access != FileAccess.Read ||
            (flags & (O_CREAT | O_TRUNC | O_APPEND)) != 0)
        {
            LogOpenTrace(
                $"_open early-dir-invalid path='{guestPath}' host='{hostPath}' flags=0x{flags:X8}");
            result = (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
            return true;
        }

        string[] entries;
        try
        {
            entries = EnumerateDirectoryEntriesForContentDiscovery(hostPath);
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException)
        {
            // Preserve a usable fd even if the host cannot enumerate children.
            // "." and ".." are enough to keep getdents semantics valid.
            entries = new[] { ".", ".." };
            Console.Error.WriteLine(
                "[LOADER][WARN] dbfz.ue_pak_directory_open enumeration-fallback " +
                $"guest='{guestPath}' host='{hostPath}' ex={ex.GetType().Name}");
        }

        var directoryFd = (int)Interlocked.Increment(ref _nextFileDescriptor);
        lock (_fdGate)
        {
            _openDirectories[directoryFd] = new OpenDirectory
            {
                Path = hostPath,
                Entries = entries,
                NextIndex = 0
            };
        }

        ctx[CpuRegister.Rax] = unchecked((ulong)directoryFd);
        result = (int)OrbisGen2Result.ORBIS_GEN2_OK;

        Console.Error.WriteLine(
            "[LOADER][WARN] dbfz.ue_pak_directory_open opened " +
            $"guest='{guestPath}' host='{hostPath}' fd={directoryFd} " +
            $"entries={entries.Length} flags=0x{flags:X8}");

        LogOpenTrace(
            $"_open early-dir path='{guestPath}' host='{hostPath}' flags=0x{flags:X8} fd={directoryFd}");

        return true;
    }
}
