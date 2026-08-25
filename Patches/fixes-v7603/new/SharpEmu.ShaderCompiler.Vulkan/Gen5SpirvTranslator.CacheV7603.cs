// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.3: process-wide compile result cache + SPIR-V disk persistence.

using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private static readonly bool CacheEnabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_SPIRV_RESULT_CACHE"),
            "0",
            StringComparison.Ordinal);

    private static readonly ConcurrentDictionary<string, Gen5SpirvShader> ResultCache = new(StringComparer.Ordinal);

    private static long _cacheHits;
    private static long _cacheMisses;
    private static long _cacheStores;

    public static long ResultCacheHits => Interlocked.Read(ref _cacheHits);
    public static long ResultCacheMisses => Interlocked.Read(ref _cacheMisses);
    public static long ResultCacheStores => Interlocked.Read(ref _cacheStores);

    internal static string BuildCompileCacheKey(
        string stage,
        Gen5ShaderState state,
        string options)
    {
        var sb = new StringBuilder(256);
        sb.Append(stage).Append('|')
          .Append(state.Program.Address.ToString("X16")).Append('|')
          .Append(state.Program.Instructions.Count).Append('|')
          .Append(options).Append('|');

        // Fingerprint first/last instruction words for collision resistance without hashing all.
        var instructions = state.Program.Instructions;
        if (instructions.Count > 0)
        {
            var first = instructions[0];
            var last = instructions[^1];
            sb.Append(first.Pc.ToString("X")).Append(':').Append(first.Opcode).Append('|');
            sb.Append(last.Pc.ToString("X")).Append(':').Append(last.Opcode).Append('|');
            // Sample mid-point
            var mid = instructions[instructions.Count / 2];
            sb.Append(mid.Pc.ToString("X")).Append(':').Append(mid.Opcode);
        }

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString()));
        return Convert.ToHexString(hash.AsSpan(0, 20));
    }

    internal static bool TryGetCachedShader(string key, out Gen5SpirvShader shader)
    {
        shader = null!;
        if (!CacheEnabled || string.IsNullOrEmpty(key))
        {
            return false;
        }

        if (ResultCache.TryGetValue(key, out shader!))
        {
            Interlocked.Increment(ref _cacheHits);
            return true;
        }

        // Disk: only SPIR-V bytes — metadata still requires a live translation.
        // Keep disk path for future full-artifact serialization; count as miss for now
        // if memory miss so translation still runs once per process.
        if (SpirvShaderDiskCache.TryLoad(key, out _))
        {
            // Bytes present but without bindings we cannot rebuild Gen5SpirvShader safely.
            // Leave as miss; Store will refresh disk after translate.
        }

        Interlocked.Increment(ref _cacheMisses);
        return false;
    }

    internal static void StoreCachedShader(string key, Gen5SpirvShader shader)
    {
        if (!CacheEnabled || string.IsNullOrEmpty(key) || shader.Spirv is null || shader.Spirv.Length == 0)
        {
            return;
        }

        ResultCache[key] = shader;
        SpirvShaderDiskCache.Store(key, shader.Spirv);
        Interlocked.Increment(ref _cacheStores);
    }

    public static string ResultCacheStatusLine() =>
        $"[SPIRV-RESULT-CACHE][V76.0.3] enabled={(CacheEnabled ? 1 : 0)} " +
        $"hits={ResultCacheHits} misses={ResultCacheMisses} stores={ResultCacheStores} " +
        $"live={ResultCache.Count}";
}
