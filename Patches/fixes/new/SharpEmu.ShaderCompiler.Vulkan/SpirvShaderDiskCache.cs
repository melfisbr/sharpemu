// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.2: persistent SPIR-V module cache to avoid re-translating hot shaders
// every launch. Major contributor to sustained 60 fps after the first session.

using System.Security.Cryptography;
using System.Text;

namespace SharpEmu.ShaderCompiler.Vulkan;

/// <summary>
/// Disk-backed cache of translated SPIR-V blobs keyed by a stable hash of the
/// guest shader program address, instruction stream and translation options.
/// Enable with SHARPEMU_SPIRV_DISK_CACHE=1 (default on). Disable with =0.
/// </summary>
public static class SpirvShaderDiskCache
{
    private static readonly bool Enabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_SPIRV_DISK_CACHE"),
            "0",
            StringComparison.Ordinal);

    private static readonly string Root = ResolveRoot();

    private static long _hits;
    private static long _misses;
    private static long _stores;

    public static long Hits => Interlocked.Read(ref _hits);
    public static long Misses => Interlocked.Read(ref _misses);
    public static long Stores => Interlocked.Read(ref _stores);

    private static string ResolveRoot()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_SPIRV_CACHE_DIR");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(Environment.ExpandEnvironmentVariables(configured));
        }

        return Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "user",
            "spirv_cache"));
    }

    public static string BuildKey(
        string stage,
        ulong programAddress,
        int instructionCount,
        ReadOnlySpan<byte> instructionFingerprint,
        string optionsFingerprint)
    {
        var material = new StringBuilder(128);
        material.Append(stage).Append('|')
            .Append(programAddress.ToString("X16")).Append('|')
            .Append(instructionCount).Append('|')
            .Append(optionsFingerprint).Append('|');

        // Prefer a short content hash of the instruction stream when available.
        if (!instructionFingerprint.IsEmpty)
        {
            var hash = SHA256.HashData(instructionFingerprint);
            material.Append(Convert.ToHexString(hash.AsSpan(0, 16)));
        }

        var keyHash = SHA256.HashData(Encoding.UTF8.GetBytes(material.ToString()));
        return Convert.ToHexString(keyHash.AsSpan(0, 20));
    }

    public static bool TryLoad(string key, out byte[] spirv)
    {
        spirv = Array.Empty<byte>();
        if (!Enabled || string.IsNullOrEmpty(key))
        {
            return false;
        }

        var path = Path.Combine(Root, key + ".spv");
        try
        {
            if (!File.Exists(path))
            {
                Interlocked.Increment(ref _misses);
                return false;
            }

            spirv = File.ReadAllBytes(path);
            if (spirv.Length < 20)
            {
                Interlocked.Increment(ref _misses);
                return false;
            }

            Interlocked.Increment(ref _hits);
            return true;
        }
        catch (IOException)
        {
            Interlocked.Increment(ref _misses);
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            Interlocked.Increment(ref _misses);
            return false;
        }
    }

    public static void Store(string key, ReadOnlySpan<byte> spirv)
    {
        if (!Enabled || string.IsNullOrEmpty(key) || spirv.Length < 20)
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(Root);
            var path = Path.Combine(Root, key + ".spv");
            var temp = path + ".tmp";
            using (var fs = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                fs.Write(spirv);
            }

            File.Move(temp, path, overwrite: true);
            Interlocked.Increment(ref _stores);
        }
        catch (IOException)
        {
            // Cache is best-effort; never block translation on disk failures.
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    public static string StatusLine() =>
        $"[SPIRV-CACHE] enabled={(Enabled ? 1 : 0)} hits={Hits} misses={Misses} stores={Stores} root={Root}";
}
