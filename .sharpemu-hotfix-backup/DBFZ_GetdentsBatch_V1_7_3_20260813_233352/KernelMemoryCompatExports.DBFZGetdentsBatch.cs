// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace SharpEmu.Libs.Kernel;

public static partial class KernelMemoryCompatExports
{
    // SHARPEMU_DBFZ_GETDENTS_BATCH_V1_7_3
    //
    // Preserve SharpEmu's existing 512-byte directory-entry layout, but return
    // as many complete records as the caller's requested buffer can hold.
    private static int KernelGetdirentriesBatchCompat(
        CpuContext ctx,
        int fd,
        ulong bufferAddress,
        int requested,
        ulong basePointerAddress)
    {
        const int RecordSize = 512;

        if (fd < 0 || bufferAddress == 0 || requested < RecordSize)
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
            LogIoTrace(
                "getdents",
                directory.Path,
                $"fd={fd} result=eof entries={directory.Entries.Length}");

            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        var capacityRecords = requested / RecordSize;
        var remainingRecords = directory.Entries.Length - startIndex;
        var recordCount = Math.Min(capacityRecords, remainingRecords);

        if (recordCount <= 0)
        {
            ctx[CpuRegister.Rax] = 0;
            return (int)OrbisGen2Result.ORBIS_GEN2_OK;
        }

        var names = new List<string>(recordCount);

        for (var record = 0; record < recordCount; record++)
        {
            var entryIndex = startIndex + record;
            var hostEntryName = directory.Entries[entryIndex];
            var guestEntryName = HostFsPath.DecodeHostPathSegment(hostEntryName);

            var entryBytes = Encoding.UTF8.GetBytes(guestEntryName);
            var nameLength = Math.Min(entryBytes.Length, 255);
            var entryPath = Path.Combine(directory.Path, hostEntryName);
            var entryType = Directory.Exists(entryPath) ? (byte)4 : (byte)8;

            var payload = new byte[RecordSize];

            BinaryPrimitives.WriteUInt32LittleEndian(
                payload.AsSpan(0, sizeof(uint)),
                ComputeDirectoryEntryHash(entryBytes.AsSpan(0, nameLength)));

            BinaryPrimitives.WriteUInt16LittleEndian(
                payload.AsSpan(4, sizeof(ushort)),
                RecordSize);

            payload[6] = entryType;
            payload[7] = unchecked((byte)nameLength);

            entryBytes
                .AsSpan(0, nameLength)
                .CopyTo(payload.AsSpan(8));

            var destination =
                bufferAddress + unchecked((ulong)(record * RecordSize));

            if (!TryWriteCompat(ctx, destination, payload))
            {
                ctx[CpuRegister.Rax] =
                    unchecked((ulong)(int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
                return (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
            }

            names.Add(guestEntryName);
        }

        lock (_fdGate)
        {
            directory.NextIndex = Math.Max(
                directory.NextIndex,
                startIndex + recordCount);
        }

        var bytesWritten = recordCount * RecordSize;
        ctx[CpuRegister.Rax] = unchecked((ulong)bytesWritten);

        var isPakDirectory =
            directory.Path.EndsWith(
                Path.Combine("red", "content", "paks"),
                StringComparison.OrdinalIgnoreCase);

        if (isPakDirectory)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] dbfz.getdents_batch paks " +
                $"fd={fd} requested={requested} start={startIndex} " +
                $"records={recordCount} bytes={bytesWritten} " +
                $"names='{string.Join("|", names)}'");
        }

        LogIoTrace(
            "getdents",
            directory.Path,
            $"fd={fd} start={startIndex} records={recordCount} bytes={bytesWritten}");

        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }
}
