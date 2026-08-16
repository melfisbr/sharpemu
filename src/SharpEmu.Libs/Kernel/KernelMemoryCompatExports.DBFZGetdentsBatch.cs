// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;

namespace SharpEmu.Libs.Kernel;

public static partial class KernelMemoryCompatExports
{
    // SHARPEMU_DIRENT_ABI_V73_0_13
    //
    // The old V1.7.3 compatibility path made every directory entry 512 bytes.
    // That was useful for the DBFZ evidence run, but it changed sceKernelGetdents
    // globally. Demon's Souls imports sceKernelGetdents too and expects the
    // FreeBSD11/Orbis layout represented by the existing fields:
    //
    //   uint32 d_fileno
    //   uint16 d_reclen
    //   uint8  d_type
    //   uint8  d_namlen
    //   char   d_name[] + NUL + padding to a 4-byte boundary
    //
    // Keep the DBFZ 512-byte compatibility record only for PPSA09790. Every
    // other title receives variable-size records, so a caller can advance by
    // d_reclen exactly as the ABI requires.
    private const int FreeBsd11DirentHeaderSize = 8;
    private const int FreeBsd11DirentMinimumRecordSize = 12;
    private const int DbfzLegacyDirentRecordSize = 512;
    private const string DragonBallFighterZTitleId = "PPSA09790";

    private static int KernelGetdirentriesBatchCompat(
        CpuContext ctx,
        int fd,
        ulong bufferAddress,
        int requested,
        ulong basePointerAddress)
    {
        var useDbfzLegacyLayout =
            IsConfiguredApplicationTitle(DragonBallFighterZTitleId);
        var minimumRecordSize = useDbfzLegacyLayout
            ? DbfzLegacyDirentRecordSize
            : FreeBsd11DirentMinimumRecordSize;

        if (fd < 0 || bufferAddress == 0 || requested < minimumRecordSize)
        {
            ctx[CpuRegister.Rax] =
                unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        OpenDirectory? directory;
        bool isOpenFile;

        lock (_fdGate)
        {
            _openDirectories.TryGetValue(fd, out directory);
            isOpenFile = directory is null && _openFiles.ContainsKey(fd);
        }

        if (directory is null)
        {
            var error = isOpenFile
                ? OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT
                : OrbisGen2Result.ORBIS_GEN2_ERROR_NOT_FOUND;

            LogIoTrace(
                "getdents",
                $"fd:{fd}",
                $"result={(isOpenFile ? "not_directory" : "badfd")}");

            ctx[CpuRegister.Rax] = unchecked((ulong)(int)error);
            return (int)error;
        }

        int startIndex;
        lock (_fdGate)
        {
            startIndex = directory.NextIndex;
        }

        if (basePointerAddress != 0 &&
            !TryWriteUInt64Compat(
                ctx,
                basePointerAddress,
                unchecked((ulong)startIndex)))
        {
            ctx[CpuRegister.Rax] =
                unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
        }

        if (startIndex >= directory.Entries.Length)
        {
            TraceDirentAbi(
                directory.Path,
                fd,
                requested,
                startIndex,
                0,
                0,
                useDbfzLegacyLayout,
                eof: true);

            LogIoTrace(
                "getdents",
                directory.Path,
                $"fd={fd} result=eof entries={directory.Entries.Length}");

            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        var bytesWritten = 0;
        var recordCount = 0;
        var names = useDbfzLegacyLayout
            ? new List<string>()
            : null;

        for (var entryIndex = startIndex;
             entryIndex < directory.Entries.Length;
             entryIndex++)
        {
            var hostEntryName = directory.Entries[entryIndex];
            var guestEntryName = HostFsPath.DecodeHostPathSegment(hostEntryName);

            var entryBytes = Encoding.UTF8.GetBytes(guestEntryName);
            var nameLength = Math.Min(entryBytes.Length, 255);
            var recordSize = useDbfzLegacyLayout
                ? DbfzLegacyDirentRecordSize
                : AlignFreeBsd11DirentRecordSize(nameLength);

            if (recordSize > requested - bytesWritten)
            {
                break;
            }

            var entryPath = Path.Combine(directory.Path, hostEntryName);
            var entryType = Directory.Exists(entryPath) ? (byte)4 : (byte)8;
            var payload = new byte[recordSize];

            BinaryPrimitives.WriteUInt32LittleEndian(
                payload.AsSpan(0, sizeof(uint)),
                ComputeDirectoryEntryHash(entryBytes.AsSpan(0, nameLength)));

            BinaryPrimitives.WriteUInt16LittleEndian(
                payload.AsSpan(4, sizeof(ushort)),
                unchecked((ushort)recordSize));

            payload[6] = entryType;
            payload[7] = unchecked((byte)nameLength);

            entryBytes
                .AsSpan(0, nameLength)
                .CopyTo(payload.AsSpan(FreeBsd11DirentHeaderSize));

            // payload is zero initialized, so d_name is NUL terminated and all
            // ABI alignment padding is deterministic.
            var destination =
                bufferAddress + unchecked((ulong)bytesWritten);

            if (!TryWriteCompat(ctx, destination, payload))
            {
                ctx[CpuRegister.Rax] =
                    unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }

            bytesWritten += recordSize;
            recordCount++;

            if (names is not null)
            {
                names.Add(guestEntryName);
            }
        }

        // A buffer large enough for the ABI minimum can still be smaller than
        // the first actual filename record. Returning EINVAL avoids reporting a
        // false EOF while the directory still has unread entries.
        if (recordCount == 0)
        {
            ctx[CpuRegister.Rax] =
                unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);

            TraceDirentAbi(
                directory.Path,
                fd,
                requested,
                startIndex,
                0,
                0,
                useDbfzLegacyLayout,
                eof: false);

            return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT;
        }

        lock (_fdGate)
        {
            directory.NextIndex = Math.Max(
                directory.NextIndex,
                startIndex + recordCount);
        }

        ctx[CpuRegister.Rax] = unchecked((ulong)bytesWritten);

        if (useDbfzLegacyLayout &&
            directory.Path.EndsWith(
                Path.Combine("red", "content", "paks"),
                StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] dbfz.getdents_batch paks " +
                $"fd={fd} requested={requested} start={startIndex} " +
                $"records={recordCount} bytes={bytesWritten} " +
                $"names='{string.Join("|", names!)}'");
        }

        TraceDirentAbi(
            directory.Path,
            fd,
            requested,
            startIndex,
            recordCount,
            bytesWritten,
            useDbfzLegacyLayout,
            eof: false);

        LogIoTrace(
            "getdents",
            directory.Path,
            $"fd={fd} start={startIndex} records={recordCount} bytes={bytesWritten} " +
            $"layout={(useDbfzLegacyLayout ? "dbfz-fixed512" : "freebsd11-variable")}");

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }

    private static int AlignFreeBsd11DirentRecordSize(int nameLength)
    {
        // offsetof(freebsd11_dirent, d_name) == 8. Include the terminating NUL
        // and round to the historical 4-byte ABI boundary.
        var rawSize = FreeBsd11DirentHeaderSize + nameLength + 1;
        return (rawSize + 3) & ~3;
    }

    private static void TraceDirentAbi(
        string path,
        int fd,
        int requested,
        int startIndex,
        int recordCount,
        int bytesWritten,
        bool useDbfzLegacyLayout,
        bool eof)
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_TRACE_DIRENT_ABI"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        Console.Error.WriteLine(
            "[V73.0.13][DIRENT] " +
            $"title={Volatile.Read(ref _applicationTitleId)} " +
            $"layout={(useDbfzLegacyLayout ? "dbfz-fixed512" : "freebsd11-variable")} " +
            $"fd={fd} requested={requested} start={startIndex} " +
            $"records={recordCount} bytes={bytesWritten} eof={(eof ? 1 : 0)} " +
            $"path='{path}'");
    }
}
