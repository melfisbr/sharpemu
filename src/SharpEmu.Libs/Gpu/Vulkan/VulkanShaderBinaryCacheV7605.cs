// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.5: collision-resistant SPIR-V binary cache for the Vulkan backend.

using System;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using SharpEmu.ShaderCompiler;
using SharpEmu.ShaderCompiler.Vulkan;

namespace SharpEmu.Libs.Gpu.Vulkan;

/// <summary>
/// Caches the final SPIR-V bytes consumed by Vulkan rather than a live
/// Gen5SpirvShader.  The latter contains per-dispatch resource/evaluation
/// metadata and must not be reused across guest submissions.
/// </summary>
internal static class VulkanShaderBinaryCacheV7605
{
    private const string CacheVersion = "V76.0.25-rdna2-crosslane-r1";
    private const int MaxCachedBinaryBytes = 32 * 1024 * 1024;

    private static readonly bool MemoryEnabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_SPIRV_RESULT_CACHE"),
            "0",
            StringComparison.Ordinal);

    private static readonly bool DiskEnabled = MemoryEnabled &&
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_SPIRV_DISK_CACHE"),
            "0",
            StringComparison.Ordinal);

    private static readonly bool Trace = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_TRACE_SPIRV_CACHE"),
        "1",
        StringComparison.Ordinal);

    private static readonly ConcurrentDictionary<string, byte[]> Memory =
        new(StringComparer.Ordinal);

    // Per-key locks prevent two render/compile threads from translating the
    // same miss simultaneously. This preserves the synchronous compile seam
    // while removing duplicate work without returning placeholder shaders.
    private static readonly ConcurrentDictionary<string, object> Gates =
        new(StringComparer.Ordinal);

    private static long _memoryHits;
    private static long _diskHits;
    private static long _misses;
    private static long _stores;
    private static long _rejectedDiskEntries;
    private static long _diskWritesQueued;
    private static long _diskWritesCompleted;
    private static readonly ConcurrentQueue<DiskWriteRequestV7610> DiskWriteQueue = new();
    private static int _diskWriterScheduled;

    // V76.0.11: warm the hottest persisted SPIR-V entries into the in-memory
    // cache on a background worker. This removes first-use File.ReadAllBytes
    // latency for shaders already compiled on a previous run without changing
    // translation semantics or returning placeholder shaders.
    private static readonly int PrewarmEntryLimitV7611 = ReadBoundedIntEnvironmentV7611(
        "SHARPEMU_SPIRV_PREWARM_MAX", 256, 0, 4096);
    private static readonly long PrewarmByteLimitV7611 =
        (long)ReadBoundedIntEnvironmentV7611(
            "SHARPEMU_SPIRV_PREWARM_MB", 64, 1, 512) * 1024 * 1024;
    private static long _prewarmEntriesV7611;
    private static long _prewarmBytesV7611;
    private static int _prewarmScheduledV7611;
    private static int _prewarmCompletedV7611;

    private sealed record DiskWriteRequestV7610(string Key, byte[] Spirv);

    static VulkanShaderBinaryCacheV7605()
    {
        ScheduleDiskPrewarmV7611();
    }

    internal static string StatusLine() =>
        $"[SPIRV-CACHE][V76.0.10] memory={(MemoryEnabled ? 1 : 0)} " +
        $"disk={(DiskEnabled ? 1 : 0)} live={Memory.Count} " +
        $"mem_hits={Interlocked.Read(ref _memoryHits)} " +
        $"disk_hits={Interlocked.Read(ref _diskHits)} " +
        $"misses={Interlocked.Read(ref _misses)} stores={Interlocked.Read(ref _stores)} " +
        $"disk_rejects={Interlocked.Read(ref _rejectedDiskEntries)} " +
        $"disk_write_queued={Interlocked.Read(ref _diskWritesQueued)} " +
        $"disk_write_done={Interlocked.Read(ref _diskWritesCompleted)} " +
        $"prewarm_scheduled={Volatile.Read(ref _prewarmScheduledV7611)} " +
        $"prewarm_done={Volatile.Read(ref _prewarmCompletedV7611)} " +
        $"prewarm_entries={Interlocked.Read(ref _prewarmEntriesV7611)} " +
        $"prewarm_bytes={Interlocked.Read(ref _prewarmBytesV7611)}";

    internal static object GateFor(string key) =>
        Gates.GetOrAdd(key, static _ => new object());

    internal static string BuildKey(
        string stage,
        Gen5ShaderState state,
        Gen5ShaderEvaluation evaluation,
        string compileOptions)
    {
        if (!MemoryEnabled)
        {
            return string.Empty;
        }

        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        AppendString(hash, CacheVersion);
        AppendString(hash, stage);
        AppendString(hash, compileOptions);
        AppendUInt64(hash, state.Program.Address);
        AppendUInt32(hash, state.UserDataScalarRegisterBase);
        AppendUInt32List(hash, state.UserData);

        // Hash every encoded guest instruction word. Address + count + a few
        // sampled opcodes (the old V76.0.3 approach) can alias shaders that
        // differ in their middle instructions.
        AppendUInt32(hash, checked((uint)state.Program.Instructions.Count));
        foreach (var instruction in state.Program.Instructions)
        {
            AppendUInt32(hash, instruction.Pc);
            AppendUInt32(hash, (uint)instruction.Encoding);
            AppendString(hash, instruction.Opcode);
            AppendUInt32List(hash, instruction.Words);
        }

        // Translation performs scalar/static resource evaluation, so its
        // result is not a pure function of instruction bytes. Include the
        // evaluated scalar state and descriptor *shape* in the key. Large
        // uploaded resource payloads are intentionally excluded: any payload
        // value that affects control flow has already propagated into the
        // scalar evaluation above, while ordinary buffer contents do not alter
        // the generated SPIR-V module.
        AppendUInt32List(hash, evaluation.InitialScalarRegisters);
        AppendUInt32List(hash, evaluation.ScalarRegisters);

        var runtimeScalars = evaluation.RuntimeScalarRegisters is null
            ? Array.Empty<uint>()
            : evaluation.RuntimeScalarRegisters.OrderBy(static value => value).ToArray();
        AppendUInt32List(hash, runtimeScalars);

        AppendUInt32(hash, checked((uint)evaluation.ImageBindings.Count));
        foreach (var image in evaluation.ImageBindings)
        {
            AppendUInt32(hash, image.Pc);
            AppendString(hash, image.Opcode);
            AppendString(hash, image.Control.ToString() ?? string.Empty);
            AppendUInt32List(hash, image.ResourceDescriptor);
            AppendUInt32List(hash, image.SamplerDescriptor);
            AppendUInt32(hash, image.MipLevel ?? uint.MaxValue);
        }

        AppendUInt32(hash, checked((uint)evaluation.GlobalMemoryBindings.Count));
        foreach (var global in evaluation.GlobalMemoryBindings)
        {
            AppendUInt32(hash, global.ScalarAddress);
            AppendUInt64(hash, global.BaseAddress);
            AppendUInt32List(hash, global.InstructionPcs);
            AppendUInt32(hash, checked((uint)Math.Max(global.DataLength, 0)));
            AppendUInt32(hash, global.Writable ? 1u : 0u);
            AppendUInt32(hash, global.WriteBackToGuest ? 1u : 0u);
        }

        var vertexInputs = evaluation.VertexInputs ?? [];
        AppendUInt32(hash, checked((uint)vertexInputs.Count));
        foreach (var vertex in vertexInputs)
        {
            AppendUInt32(hash, vertex.Pc);
            AppendUInt32(hash, vertex.Location);
            AppendUInt32(hash, vertex.ComponentCount);
            AppendUInt32(hash, vertex.DataFormat);
            AppendUInt32(hash, vertex.NumberFormat);
            AppendUInt64(hash, vertex.BaseAddress);
            AppendUInt32(hash, vertex.Stride);
            AppendUInt32(hash, vertex.OffsetBytes);
            AppendUInt32(hash, vertex.PerInstance ? 1u : 0u);
            AppendUInt32List(hash, vertex.AliasPcs ?? []);
        }

        AppendString(hash, state.ComputeSystemRegisters?.ToString() ?? string.Empty);
        AppendString(hash, evaluation.ComputeSystemRegisters?.ToString() ?? string.Empty);

        // Metadata participates in descriptor/resource lowering. Record.ToString()
        // only prints collection type names for nested dictionaries/lists, so hash
        // the metadata fields structurally to prevent cross-shader collisions.
        if (state.Metadata is { } metadata)
        {
            AppendUInt32(hash, 1);
            AppendUInt32(hash, metadata.ExtendedUserDataSizeDwords);
            AppendUInt32(hash, metadata.ShaderResourceTableSizeDwords);
            AppendUInt32(hash, checked((uint)metadata.DirectResources.Count));
            foreach (var direct in metadata.DirectResources.OrderBy(static item => item.Key))
            {
                AppendUInt32(hash, direct.Key);
                AppendUInt32(hash, direct.Value);
            }

            AppendUInt32(hash, checked((uint)metadata.Resources.Count));
            foreach (var resource in metadata.Resources)
            {
                AppendUInt32(hash, (uint)resource.Kind);
                AppendUInt32(hash, resource.Slot);
                AppendUInt32(hash, resource.OffsetDwords);
                AppendUInt32(hash, resource.SizeFlag ? 1u : 0u);
            }
        }
        else
        {
            AppendUInt32(hash, 0);
        }

        // V76.0.10: only compiler-semantic environment switches belong in the
        // binary key. The old V76.0.5.1 implementation hashed every SHARPEMU_*
        // variable, so enabling telemetry (present cadence, compute timing, cache
        // traces, etc.) generated a completely different disk cache even though
        // the emitted SPIR-V was byte-for-byte identical. Keep future shader/GEN5
        // semantic switches conservative while excluding known cache/diagnostic
        // controls.
        var environment = Environment.GetEnvironmentVariables();
        var shaderEnvironment = new List<(string Name, string Value)>();
        foreach (System.Collections.DictionaryEntry entry in environment)
        {
            if (entry.Key is string name && IsSemanticShaderEnvironmentV7610(name))
            {
                shaderEnvironment.Add((name, entry.Value?.ToString() ?? string.Empty));
            }
        }
        shaderEnvironment.Sort(static (left, right) =>
            StringComparer.Ordinal.Compare(left.Name, right.Name));
        AppendUInt32(hash, checked((uint)shaderEnvironment.Count));
        foreach (var item in shaderEnvironment)
        {
            AppendString(hash, item.Name);
            AppendString(hash, item.Value);
        }

        return Convert.ToHexString(hash.GetHashAndReset());
    }

    internal static bool TryGet(string key, out byte[] spirv)
    {
        spirv = [];
        if (!MemoryEnabled || string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        if (Memory.TryGetValue(key, out spirv!))
        {
            Interlocked.Increment(ref _memoryHits);
            TraceHit("memory", key, spirv.Length);
            return true;
        }

        if (DiskEnabled && TryReadDisk(key, out spirv))
        {
            Memory[key] = spirv;
            Interlocked.Increment(ref _diskHits);
            TraceHit("disk", key, spirv.Length);
            return true;
        }

        return false;
    }

    internal delegate bool TranslateSpirv(out byte[] spirv, out string error);

    internal static bool TryGetOrTranslate(
        string key,
        TranslateSpirv translate,
        out byte[] spirv,
        out string error,
        out bool cacheHit)
    {
        if (!MemoryEnabled)
        {
            cacheHit = false;
            return translate(out spirv, out error);
        }

        if (TryGet(key, out spirv))
        {
            error = string.Empty;
            cacheHit = true;
            return true;
        }

        lock (GateFor(key))
        {
            if (TryGet(key, out spirv))
            {
                error = string.Empty;
                cacheHit = true;
                return true;
            }

            Interlocked.Increment(ref _misses);
            cacheHit = false;
            if (!translate(out spirv, out error))
            {
                spirv = [];
                return false;
            }

            Store(key, spirv);
            return true;
        }
    }

    internal static void Store(string key, byte[] spirv)
    {
        if (!MemoryEnabled || string.IsNullOrWhiteSpace(key) ||
            spirv.Length == 0 || spirv.Length > MaxCachedBinaryBytes)
        {
            return;
        }

        if (!Gen5SpirvTranslator.TryValidateBinaryV7605(spirv, out _))
        {
            return;
        }

        Memory[key] = spirv;
        Interlocked.Increment(ref _stores);
        if (DiskEnabled)
        {
            QueueDiskWriteV7610(key, spirv);
        }
    }


    private static bool IsSemanticShaderEnvironmentV7610(string name)
    {
        // Debug/trace switches never alter generated SPIR-V.
        if (name.StartsWith("SHARPEMU_TRACE_", StringComparison.Ordinal))
        {
            return false;
        }

        if (name is
            "SHARPEMU_SPIRV_RESULT_CACHE" or
            "SHARPEMU_SPIRV_DISK_CACHE" or
            "SHARPEMU_SPIRV_CACHE_DIR" or
            "SHARPEMU_SHADER_DECODE_CACHE_MAX" or
            "SHARPEMU_SHADER_METADATA_CACHE_MAX")
        {
            return false;
        }

        return name.StartsWith("SHARPEMU_SHADER_", StringComparison.Ordinal) ||
            name.StartsWith("SHARPEMU_GEN5_", StringComparison.Ordinal) ||
            name.StartsWith("SHARPEMU_STRICT_", StringComparison.Ordinal) ||
            (name is
                "SHARPEMU_CFG_RESOURCE_DISCOVERY" or
                "SHARPEMU_FORCE_PIXEL_MAGENTA" or
                "SHARPEMU_IR_DESCRIPTOR_GUARD") ||
            (name.StartsWith("SHARPEMU_SPIRV_", StringComparison.Ordinal) &&
             !name.StartsWith("SHARPEMU_SPIRV_CACHE", StringComparison.Ordinal));
    }

    private static void QueueDiskWriteV7610(string key, byte[] spirv)
    {
        DiskWriteQueue.Enqueue(new DiskWriteRequestV7610(key, spirv));
        Interlocked.Increment(ref _diskWritesQueued);
        if (Interlocked.CompareExchange(ref _diskWriterScheduled, 1, 0) != 0)
        {
            return;
        }

        ThreadPool.QueueUserWorkItem(
            static _ => DrainDiskWritesV7610());
    }

    private static void DrainDiskWritesV7610()
    {
        while (true)
        {
            while (DiskWriteQueue.TryDequeue(out var request))
            {
                TryWriteDisk(request.Key, request.Spirv);
                Interlocked.Increment(ref _diskWritesCompleted);
            }

            Volatile.Write(ref _diskWriterScheduled, 0);
            if (DiskWriteQueue.IsEmpty ||
                Interlocked.CompareExchange(ref _diskWriterScheduled, 1, 0) != 0)
            {
                return;
            }
        }
    }

    private static int ReadBoundedIntEnvironmentV7611(
        string name,
        int fallback,
        int minimum,
        int maximum)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return int.TryParse(value, out var parsed)
            ? Math.Clamp(parsed, minimum, maximum)
            : fallback;
    }

    private static void ScheduleDiskPrewarmV7611()
    {
        if (!MemoryEnabled || !DiskEnabled || PrewarmEntryLimitV7611 <= 0 ||
            Interlocked.CompareExchange(ref _prewarmScheduledV7611, 1, 0) != 0)
        {
            return;
        }

        ThreadPool.QueueUserWorkItem(static _ => PrewarmDiskCacheV7611());
    }

    private static void PrewarmDiskCacheV7611()
    {
        try
        {
            // Do not contend with immediate device/guest startup I/O. The work
            // remains opportunistic: a foreground lookup can still win the key.
            Thread.Sleep(100);
            var directory = ResolveCacheDirectory();
            if (directory is null || !Directory.Exists(directory))
            {
                return;
            }

            var candidates = Directory
                .EnumerateFiles(directory, "*.spv", SearchOption.TopDirectoryOnly)
                .Select(static path => new FileInfo(path))
                .Where(static info =>
                    info.Exists && info.Length > 0 && info.Length <= MaxCachedBinaryBytes)
                .OrderByDescending(static info => info.LastWriteTimeUtc)
                .Take(PrewarmEntryLimitV7611)
                .ToArray();

            long acceptedBytes = 0;
            foreach (var info in candidates)
            {
                if (acceptedBytes >= PrewarmByteLimitV7611)
                {
                    break;
                }

                var key = Path.GetFileNameWithoutExtension(info.Name);
                if (key.Length != 64 || Memory.ContainsKey(key))
                {
                    continue;
                }

                try
                {
                    var bytes = File.ReadAllBytes(info.FullName);
                    if (bytes.Length == 0 || bytes.Length > MaxCachedBinaryBytes ||
                        acceptedBytes + bytes.Length > PrewarmByteLimitV7611)
                    {
                        continue;
                    }

                    if (!Gen5SpirvTranslator.TryValidateBinaryV7605(bytes, out _))
                    {
                        Interlocked.Increment(ref _rejectedDiskEntries);
                        TryDelete(info.FullName);
                        continue;
                    }

                    if (Memory.TryAdd(key, bytes))
                    {
                        acceptedBytes += bytes.Length;
                        Interlocked.Increment(ref _prewarmEntriesV7611);
                        Interlocked.Add(ref _prewarmBytesV7611, bytes.Length);
                    }
                }
                catch
                {
                    // Prewarm is strictly opportunistic and cannot fail startup.
                }
            }
        }
        catch
        {
            // Directory enumeration/cache access must never fail emulator startup.
        }
        finally
        {
            Volatile.Write(ref _prewarmCompletedV7611, 1);
            if (Trace)
            {
                Console.Error.WriteLine(
                    $"[SPIRV-CACHE][V76.0.11][PREWARM] entries={Interlocked.Read(ref _prewarmEntriesV7611)} " +
                    $"bytes={Interlocked.Read(ref _prewarmBytesV7611)}");
            }
        }
    }

    private static string? ResolveCacheDirectory()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_SPIRV_CACHE_DIR");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return configured;
        }

        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return string.IsNullOrWhiteSpace(local)
            ? null
            : Path.Combine(local, "SharpEmu", "ShaderCache", "V76.0.10");
    }

    private static bool TryReadDisk(string key, out byte[] spirv)
    {
        spirv = [];
        var directory = ResolveCacheDirectory();
        if (directory is null)
        {
            return false;
        }

        var path = Path.Combine(directory, key + ".spv");
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.Length <= 0 || info.Length > MaxCachedBinaryBytes)
            {
                return false;
            }

            var bytes = File.ReadAllBytes(path);
            if (!Gen5SpirvTranslator.TryValidateBinaryV7605(bytes, out _))
            {
                Interlocked.Increment(ref _rejectedDiskEntries);
                TryDelete(path);
                return false;
            }

            spirv = bytes;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void TryWriteDisk(string key, byte[] spirv)
    {
        var directory = ResolveCacheDirectory();
        if (directory is null)
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, key + ".spv");
            if (File.Exists(path))
            {
                return;
            }

            var temp = path + $".{Environment.ProcessId}.{Environment.CurrentManagedThreadId}.tmp";
            File.WriteAllBytes(temp, spirv);
            try
            {
                File.Move(temp, path, overwrite: false);
            }
            catch (IOException)
            {
                // Another compile thread/process won the same cache key.
                TryDelete(temp);
            }
        }
        catch
        {
            // Cache persistence must never make shader compilation fail.
        }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch { }
    }

    private static void TraceHit(string tier, string key, int bytes)
    {
        if (Trace)
        {
            Console.Error.WriteLine(
                $"[SPIRV-CACHE][V76.0.10] hit={tier} key={key[..Math.Min(16, key.Length)]} bytes={bytes}");
        }
    }

    private static void AppendString(IncrementalHash hash, string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        AppendUInt32(hash, checked((uint)bytes.Length));
        hash.AppendData(bytes);
    }

    private static void AppendUInt32List(IncrementalHash hash, IReadOnlyCollection<uint> values)
    {
        AppendUInt32(hash, checked((uint)values.Count));
        foreach (var value in values)
        {
            AppendUInt32(hash, value);
        }
    }

    private static void AppendUInt32(IncrementalHash hash, uint value)
    {
        Span<byte> bytes = stackalloc byte[sizeof(uint)];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes, value);
        hash.AppendData(bytes);
    }

    private static void AppendUInt64(IncrementalHash hash, ulong value)
    {
        Span<byte> bytes = stackalloc byte[sizeof(ulong)];
        BinaryPrimitives.WriteUInt64LittleEndian(bytes, value);
        hash.AppendData(bytes);
    }
}
