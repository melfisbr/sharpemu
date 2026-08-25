// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text;

namespace SharpEmu.Libs.Ampr;

internal static class AmprFileRegistry
{
    private const uint CacheMagicV2 = 0x32495041u; // 'API2'
    private const uint CacheVersionV2 = 2;
    private const uint CacheMagicV3 = 0x33495041u; // 'API3'
    private const uint CacheVersionV3 = 3;

    private static readonly ConcurrentDictionary<uint, string> _hostPathsById = new(
        concurrencyLevel: Math.Max(4, Environment.ProcessorCount),
        capacity: 1_048_576);
    private static readonly object _indexGate = new();
    private static string? _indexedApp0Root;
    private static string? _indexingApp0Root;
    private static int _preloadStarted;

    // SHARPEMU_V74_0_42_CANONICAL_APR_APP0_INDEX
    // Demon's Souls precomputed APR ids observed in runtime are FNV-1a hashes
    // of the canonical "$/<relative>" path. The legacy app0 preload inserted
    // four namespace aliases for every file into one uint->path dictionary.
    // With ~223k files that creates ~893k 32-bit keys and lets an alias hash
    // silently overwrite a canonical "$/" id. Because the index is filled in
    // parallel, the collision winner can also vary between runs.
    //
    // Under this title-scoped A/B, preload/cache restore publishes only the
    // canonical "$/" id. Explicit non-app0 paths keep their existing behavior.
    private static readonly bool _canonicalApp0IndexV74042 = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_AMPR_CANONICAL_APP0_INDEX"),
        "1",
        StringComparison.Ordinal);
    private static readonly ConcurrentDictionary<
        uint,
        ConcurrentDictionary<string, byte>> _canonicalCollisionCandidatesV74042 = new();
    private static long _v74042CanonicalCollisionTraceCount;

    // SHARPEMU_V74_0_42_4_CANONICAL_COLLISION_QUARANTINE
    // A true canonical FNV32 collision is not safely resolvable from the id
    // alone. Keep colliding preload entries out of the one-to-one registry
    // until the guest explicitly resolves one of the colliding paths.
    private static readonly ConcurrentDictionary<uint, string>
        _canonicalExplicitPathV740424 = new();
    private static long _v740424AmbiguousLookupTraceCount;
    private static long _v740424ExplicitResolveTraceCount;
    private static long _v740424QuarantineTraceCount;

    public static uint Register(string guestPath, string hostPath)
    {
        if (TryGetApp0Relative(guestPath, out var relative) && relative.Length != 0)
        {
            if (_canonicalApp0IndexV74042)
            {
                var canonicalId = ComputeApp0CanonicalId(relative);
                PublishCanonicalExactV740424(canonicalId, hostPath);
                return canonicalId;
            }

            RegisterApp0Relative(relative, hostPath);
            return ComputeFileId("$/" + relative);
        }

        var id = ComputeFileId(guestPath);
        _hostPathsById[id] = hostPath;
        return id;
    }

    public static bool TryGetHostPath(uint id, out string hostPath)
    {
        if (_canonicalApp0IndexV74042 &&
            _canonicalCollisionCandidatesV74042.TryGetValue(id, out var candidates))
        {
            if (_canonicalExplicitPathV740424.TryGetValue(id, out hostPath!))
            {
                return true;
            }

            var traceCount = Interlocked.Increment(
                ref _v740424AmbiguousLookupTraceCount);
            if (traceCount <= 64 || (traceCount & (traceCount - 1)) == 0)
            {
                string? first = null;
                string? second = null;
                foreach (var candidate in candidates.Keys)
                {
                    if (first is null)
                    {
                        first = candidate;
                    }
                    else
                    {
                        second = candidate;
                        break;
                    }
                }

                Console.Error.WriteLine(
                    $"[V74.0.42.4][APR_AMBIGUOUS_LOOKUP] count={traceCount} " +
                    $"id=0x{id:X8} candidates={candidates.Count} " +
                    $"a='{first ?? string.Empty}' b='{second ?? string.Empty}'; " +
                    "refusing arbitrary wrong-file selection");
            }

            hostPath = string.Empty;
            return false;
        }

        return _hostPathsById.TryGetValue(id, out hostPath!);
    }

    /// <summary>Test hook: wipe registry state between cases.</summary>
    internal static void ClearForTests()
    {
        lock (_indexGate)
        {
            _hostPathsById.Clear();
            _canonicalCollisionCandidatesV74042.Clear();
            _canonicalExplicitPathV740424.Clear();
            _indexedApp0Root = null;
            _indexingApp0Root = null;
            _preloadStarted = 0;
            Interlocked.Exchange(ref _v74042CanonicalCollisionTraceCount, 0);
            Interlocked.Exchange(ref _v740424AmbiguousLookupTraceCount, 0);
            Interlocked.Exchange(ref _v740424ExplicitResolveTraceCount, 0);
            Interlocked.Exchange(ref _v740424QuarantineTraceCount, 0);
        }
    }

    /// <summary>Test hook for the allocation-free alias publisher.</summary>
    internal static void RegisterApp0RelativeForTests(string relative, string hostPath) =>
        RegisterApp0Relative(relative, hostPath);

    /// <summary>
    /// Kick off <see cref="EnsureApp0Indexed"/> on a background thread as soon as
    /// the host knows app0. otherwise pays the full tree walk on the
    /// first cooked-id APR miss mid-boot (~8s under Rosetta for DeS).
    /// </summary>
    public static void BeginApp0IndexPreload(string? app0Root)
    {
        if (string.IsNullOrWhiteSpace(app0Root) || !Directory.Exists(app0Root))
        {
            return;
        }

        if (Interlocked.Exchange(ref _preloadStarted, 1) != 0)
        {
            return;
        }

        var root = app0Root;
        ThreadPool.UnsafeQueueUserWorkItem(
            static state =>
            {
                try
                {
                    EnsureApp0Indexed((string)state!);
                }
                catch (Exception exception)
                {
                    Console.Error.WriteLine(
                        $"[LOADER][WARN] ampr.app0_index_preload_failed: {exception.Message}");
                }
            },
            root);
    }

    /// <summary>
    /// Indexes every file under app0 under both <c>$/</c> and <c>/app0/</c> FNV
    /// ids. Cooked asset tables ship precomputed ids; without this walk, a title
    /// that never resolves those paths through APR leaves ReadFile permanently
    /// NOT_FOUND.
    /// </summary>
    public static void EnsureApp0Indexed(string app0Root)
    {
        if (string.IsNullOrWhiteSpace(app0Root) || !Directory.Exists(app0Root))
        {
            return;
        }

        var normalizedRoot = Path.GetFullPath(app0Root);
        var stopwatch = Stopwatch.StartNew();

        lock (_indexGate)
        {
            while (true)
            {
                if (string.Equals(_indexedApp0Root, normalizedRoot, HostFsPath.Comparison))
                {
                    return;
                }

                if (_indexingApp0Root is not null)
                {
                    // Another thread (preload) owns the walk — wait instead of
                    // stacking a second 8s index on the guest APR miss path.
                    if (string.Equals(
                            _indexingApp0Root,
                            normalizedRoot,
                            HostFsPath.Comparison))
                    {
                        Monitor.Wait(_indexGate);
                        continue;
                    }

                    Monitor.Wait(_indexGate, 50);
                    continue;
                }

                _indexingApp0Root = normalizedRoot;
                break;
            }
        }

        try
        {
            var cachePathV3 = GetIndexCachePath(normalizedRoot, version: 3);
            var cachePathV2 = GetIndexCachePath(normalizedRoot, version: 2);
            if (TryLoadIndexCache(normalizedRoot, cachePathV3, preferV3: true, out var cachedFiles))
            {
                lock (_indexGate)
                {
                    _indexedApp0Root = normalizedRoot;
                }

                Console.Error.WriteLine(
                    $"[LOADER][INFO] ampr.app0_index_cache_hit root={normalizedRoot} " +
                    $"files={cachedFiles} ids={_hostPathsById.Count} " +
                    $"mode={(_canonicalApp0IndexV74042 ? "canonical-only" : "legacy-four-alias")} " +
                    $"canonical_collisions={Volatile.Read(ref _v74042CanonicalCollisionTraceCount)} " +
                    $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1}");
                return;
            }

            if (TryLoadIndexCache(normalizedRoot, cachePathV2, preferV3: false, out cachedFiles))
            {
                lock (_indexGate)
                {
                    _indexedApp0Root = normalizedRoot;
                }

                // Promote v2 (rehash-on-load) to v3 (precomputed ids) so the
                // next boot skips the Rosetta FNV storm.
                TrySaveIndexCache(normalizedRoot, cachePathV3, cachedFiles);
                Console.Error.WriteLine(
                    $"[LOADER][INFO] ampr.app0_index_cache_hit root={normalizedRoot} " +
                    $"files={cachedFiles} ids={_hostPathsById.Count} " +
                    $"mode={(_canonicalApp0IndexV74042 ? "canonical-only" : "legacy-four-alias")} " +
                    $"canonical_collisions={Volatile.Read(ref _v74042CanonicalCollisionTraceCount)} " +
                    $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1} upgraded=v3");
                return;
            }

            var relatives = new List<string>(256 * 1024);
            try
            {
                foreach (var hostPath in Directory.EnumerateFiles(
                             normalizedRoot,
                             "*",
                             SearchOption.AllDirectories))
                {
                    var relative = Path.GetRelativePath(normalizedRoot, hostPath)
                        .Replace('\\', '/');
                    if (string.IsNullOrEmpty(relative) ||
                        relative.StartsWith("..", StringComparison.Ordinal))
                    {
                        continue;
                    }

                    relatives.Add(relative);
                }
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                // The walk is an opportunistic warm-up reached synchronously from
                // sceAmprCommandBufferConstructor; a dump that moves or a mount
                // that hiccups must not fault the guest export. The background
                // preload already swallows this. Leave the root unindexed so a
                // later call retries.
                Console.Error.WriteLine(
                    $"[LOADER][WARN] ampr.app0_index_walk_failed root={normalizedRoot}: {exception.Message}");
                return;
            }

            // Hash + dictionary fill dominates under Rosetta once the walk is
            // done; parallelize across cores without re-walking the tree.
            Parallel.ForEach(
                relatives,
                new ParallelOptions
                {
                    MaxDegreeOfParallelism = Math.Max(2, Environment.ProcessorCount - 1),
                },
                relative =>
                {
                    var hostPath = Path.Combine(normalizedRoot, relative.Replace('/', Path.DirectorySeparatorChar));
                    RegisterApp0RelativeForIndexV74042(relative, hostPath);
                });

            lock (_indexGate)
            {
                _indexedApp0Root = normalizedRoot;
            }

            TrySaveIndexCache(normalizedRoot, cachePathV3, relatives.Count);
            Console.Error.WriteLine(
                $"[LOADER][INFO] ampr.app0_indexed root={normalizedRoot} " +
                $"files={relatives.Count} ids={_hostPathsById.Count} " +
                $"mode={(_canonicalApp0IndexV74042 ? "canonical-only" : "legacy-four-alias")} " +
                $"canonical_collisions={Volatile.Read(ref _v74042CanonicalCollisionTraceCount)} " +
                $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1}");
        }
        finally
        {
            lock (_indexGate)
            {
                _indexingApp0Root = null;
                Monitor.PulseAll(_indexGate);
            }
        }
    }

    private static void RegisterApp0RelativeForIndexV74042(
        string relative,
        string hostPath)
    {
        if (_canonicalApp0IndexV74042)
        {
            PublishCanonicalV74042(
                ComputeApp0CanonicalId(relative),
                hostPath);
            return;
        }

        RegisterApp0Relative(relative, hostPath);
    }

    private static uint ComputeApp0CanonicalId(string relative) =>
        FnvContinueUtf8(
            FnvContinueAscii(
                FnvContinueAscii(OffsetBasis, (byte)'$'),
                (byte)'/'),
            relative);

    private static void PublishCanonicalExactV740424(uint id, string hostPath)
    {
        _canonicalExplicitPathV740424[id] = hostPath;
        _hostPathsById[id] = hostPath;

        if (_canonicalCollisionCandidatesV74042.TryGetValue(id, out var candidates))
        {
            _ = candidates.TryAdd(hostPath, 0);
            var traceCount = Interlocked.Increment(
                ref _v740424ExplicitResolveTraceCount);
            if (traceCount <= 64 || (traceCount & (traceCount - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.42.4][APR_EXPLICIT_COLLISION_RESOLVE] count={traceCount} " +
                    $"id=0x{id:X8} candidates={candidates.Count} path='{hostPath}'");
            }
        }
    }

    private static void PublishCanonicalV74042(uint id, string hostPath)
    {
        while (true)
        {
            if (_canonicalCollisionCandidatesV74042.TryGetValue(
                    id,
                    out var knownCandidates))
            {
                _ = knownCandidates.TryAdd(hostPath, 0);
                if (_canonicalExplicitPathV740424.TryGetValue(id, out var exactPath))
                {
                    _hostPathsById[id] = exactPath;
                }
                else
                {
                    _hostPathsById.TryRemove(id, out _);
                }

                return;
            }

            if (!_hostPathsById.TryGetValue(id, out var existing))
            {
                if (_canonicalExplicitPathV740424.TryGetValue(id, out var exactPath))
                {
                    _hostPathsById[id] = exactPath;
                    return;
                }

                if (_hostPathsById.TryAdd(id, hostPath))
                {
                    return;
                }

                continue;
            }

            if (HostFsPath.Comparer.Equals(existing, hostPath))
            {
                return;
            }

            var candidates = _canonicalCollisionCandidatesV74042.GetOrAdd(
                id,
                static _ => new ConcurrentDictionary<string, byte>(
                    HostFsPath.Comparer));
            _ = candidates.TryAdd(existing, 0);
            var added = candidates.TryAdd(hostPath, 0);
            if (added)
            {
                var traceCount = Interlocked.Increment(
                    ref _v74042CanonicalCollisionTraceCount);
                if (traceCount <= 64 ||
                    (traceCount & (traceCount - 1)) == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.42][APR_CANONICAL_COLLISION] count={traceCount} " +
                        $"id=0x{id:X8} candidates={candidates.Count} " +
                        $"existing='{existing}' incoming='{hostPath}'");
                }
            }

            if (_canonicalExplicitPathV740424.TryGetValue(id, out var exact))
            {
                _hostPathsById[id] = exact;
                return;
            }

            // Do not choose a deterministic-but-arbitrary file for a true
            // canonical collision. A wrong successful read is more dangerous
            // than NOT_FOUND because the guest may parse unrelated bytes as a
            // mesh/audio/resource structure and corrupt its native heap.
            _hostPathsById.TryRemove(id, out _);
            var quarantineCount = Interlocked.Increment(
                ref _v740424QuarantineTraceCount);
            if (quarantineCount <= 64 ||
                (quarantineCount & (quarantineCount - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.42.4][APR_CANONICAL_QUARANTINE] count={quarantineCount} " +
                    $"id=0x{id:X8} candidates={candidates.Count}; mapping removed");
            }

            return;
        }
    }

    /// <summary>
    /// Registers the four Insomniac path aliases for one app0-relative file
    /// without allocating intermediate guest-path strings.
    /// </summary>
    private static void RegisterApp0Relative(string relative, string hostPath)
    {
        // "$/" + relative
        Publish(FnvContinueAscii(FnvContinueAscii(OffsetBasis, (byte)'$'), (byte)'/'), relative, hostPath);
        // "/app0/" + relative
        Publish(FnvContinueAsciiPrefix(OffsetBasis, "/app0/"u8), relative, hostPath);
        // "app0/" + relative
        Publish(FnvContinueAsciiPrefix(OffsetBasis, "app0/"u8), relative, hostPath);
        // bare relative
        Publish(OffsetBasis, relative, hostPath);
    }

    private static void Publish(uint hash, string relative, string hostPath)
    {
        _hostPathsById[FnvContinueUtf8(hash, relative)] = hostPath;
    }

    internal static uint ComputeFileId(string guestPath)
    {
        return FnvContinueUtf8(OffsetBasis, guestPath);
    }

    internal static IEnumerable<string> EnumerateApp0PathAliases(string guestPath)
    {
        if (string.IsNullOrEmpty(guestPath))
        {
            yield break;
        }

        if (!TryGetApp0Relative(guestPath, out var relative) ||
            string.IsNullOrEmpty(relative))
        {
            yield break;
        }

        yield return "$/" + relative;
        yield return "/app0/" + relative;
        yield return "app0/" + relative;
        yield return relative;
    }

    private static bool TryGetApp0Relative(string guestPath, out string relative)
    {
        relative = string.Empty;
        var normalized = guestPath.Replace('\\', '/');

        if (normalized.StartsWith("$/", StringComparison.Ordinal))
        {
            relative = normalized[2..].TrimStart('/');
            return relative.Length != 0;
        }

        if (normalized.StartsWith("/app0/", StringComparison.OrdinalIgnoreCase))
        {
            relative = normalized["/app0/".Length..].TrimStart('/');
            return relative.Length != 0;
        }

        if (normalized.StartsWith("app0/", StringComparison.OrdinalIgnoreCase))
        {
            relative = normalized["app0/".Length..].TrimStart('/');
            return relative.Length != 0;
        }

        // Bare relative paths are treated as app0-relative by ResolveGuestPath.
        if (!normalized.StartsWith('/') &&
            !Path.IsPathFullyQualified(guestPath))
        {
            relative = normalized.TrimStart('/');
            return relative.Length != 0;
        }

        return false;
    }

    private static string GetIndexCachePath(string normalizedRoot, int version)
    {
        var overrideDir = Environment.GetEnvironmentVariable("SHARPEMU_AMPR_INDEX_CACHE");
        var cacheDir = !string.IsNullOrWhiteSpace(overrideDir)
            ? overrideDir
            : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SharpEmu",
                "ampr-index");
        Directory.CreateDirectory(cacheDir);

        // Distinct roots must not share a cache file. Folding case is only
        // correct where the host filesystem folds it too.
        var rootKey = OperatingSystem.IsWindows() ? normalizedRoot.ToLowerInvariant() : normalizedRoot;
        var rootHash = ComputeFileId(rootKey);
        return Path.Combine(cacheDir, $"app0-{rootHash:x8}.v{version}.idx");
    }

    private static bool TryLoadIndexCache(
        string normalizedRoot,
        string cachePath,
        bool preferV3,
        out int fileCount)
    {
        fileCount = 0;
        try
        {
            if (!File.Exists(cachePath))
            {
                return false;
            }

            if (string.Equals(
                    Environment.GetEnvironmentVariable("SHARPEMU_AMPR_REINDEX"),
                    "1",
                    StringComparison.Ordinal))
            {
                return false;
            }

            using var stream = File.OpenRead(cachePath);
            using var reader = new BinaryReader(stream, Encoding.UTF8, leaveOpen: false);
            var magic = reader.ReadUInt32();
            var version = reader.ReadUInt32();
            var isV3 = magic == CacheMagicV3 && version == CacheVersionV3;
            var isV2 = magic == CacheMagicV2 && version == CacheVersionV2;
            if (preferV3)
            {
                if (!isV3)
                {
                    return false;
                }
            }
            else if (!isV2)
            {
                return false;
            }

            var root = reader.ReadString();
            if (!string.Equals(root, normalizedRoot, HostFsPath.Comparison))
            {
                return false;
            }

            var expectedFiles = reader.ReadInt32();
            var expectedParamTicks = reader.ReadInt64();
            var actualParamTicks = GetParamJsonWriteTicks(normalizedRoot);
            if (actualParamTicks == 0 || actualParamTicks != expectedParamTicks)
            {
                return false;
            }

            if (expectedFiles < 0 || expectedFiles > 8_000_000)
            {
                return false;
            }

            if (isV3)
            {
                // Precomputed FNV ids — no Rosetta hash storm on every boot.
                var entries = new (string Relative, uint Id0, uint Id1, uint Id2, uint Id3)[expectedFiles];
                for (var i = 0; i < expectedFiles; i++)
                {
                    entries[i] = (
                        reader.ReadString(),
                        reader.ReadUInt32(),
                        reader.ReadUInt32(),
                        reader.ReadUInt32(),
                        reader.ReadUInt32());
                }

                Parallel.ForEach(
                    entries,
                    new ParallelOptions
                    {
                        MaxDegreeOfParallelism = Math.Max(2, Environment.ProcessorCount - 1),
                    },
                    entry =>
                    {
                        if (string.IsNullOrEmpty(entry.Relative) ||
                            entry.Relative.Contains("..", StringComparison.Ordinal))
                        {
                            return;
                        }

                        var hostPath = normalizedRoot.EndsWith(Path.DirectorySeparatorChar)
                            ? normalizedRoot + entry.Relative.Replace('/', Path.DirectorySeparatorChar)
                            : normalizedRoot + Path.DirectorySeparatorChar +
                              entry.Relative.Replace('/', Path.DirectorySeparatorChar);
                        if (_canonicalApp0IndexV74042)
                        {
                            PublishCanonicalV74042(entry.Id0, hostPath);
                        }
                        else
                        {
                            _hostPathsById[entry.Id0] = hostPath;
                            _hostPathsById[entry.Id1] = hostPath;
                            _hostPathsById[entry.Id2] = hostPath;
                            _hostPathsById[entry.Id3] = hostPath;
                        }
                    });
            }
            else
            {
                var relatives = new string[expectedFiles];
                for (var i = 0; i < expectedFiles; i++)
                {
                    relatives[i] = reader.ReadString();
                }

                Parallel.ForEach(
                    relatives,
                    new ParallelOptions
                    {
                        MaxDegreeOfParallelism = Math.Max(2, Environment.ProcessorCount - 1),
                    },
                    relative =>
                    {
                        if (string.IsNullOrEmpty(relative) ||
                            relative.Contains("..", StringComparison.Ordinal))
                        {
                            return;
                        }

                        var hostPath = Path.Combine(
                            normalizedRoot,
                            relative.Replace('/', Path.DirectorySeparatorChar));
                        RegisterApp0RelativeForIndexV74042(relative, hostPath);
                    });
            }

            fileCount = expectedFiles;
            return true;
        }
        catch (Exception exception)
        {
            _hostPathsById.Clear();
            _canonicalCollisionCandidatesV74042.Clear();
            _canonicalExplicitPathV740424.Clear();
            Interlocked.Exchange(ref _v74042CanonicalCollisionTraceCount, 0);
            Interlocked.Exchange(ref _v740424AmbiguousLookupTraceCount, 0);
            Interlocked.Exchange(ref _v740424ExplicitResolveTraceCount, 0);
            Interlocked.Exchange(ref _v740424QuarantineTraceCount, 0);
            Console.Error.WriteLine(
                $"[LOADER][WARN] ampr.app0_index_cache_load_failed: {exception.Message}");
            return false;
        }
    }

    private static void TrySaveIndexCache(
        string normalizedRoot,
        string cachePath,
        int fileCount)
    {
        try
        {
            var paramTicks = GetParamJsonWriteTicks(normalizedRoot);
            if (paramTicks == 0 || fileCount <= 0)
            {
                return;
            }

            var relatives = new HashSet<string>(HostFsPath.Comparer);
            foreach (var hostPath in _hostPathsById.Values)
            {
                var relative = Path.GetRelativePath(normalizedRoot, hostPath)
                    .Replace('\\', '/');
                if (string.IsNullOrEmpty(relative) ||
                    relative.StartsWith("..", StringComparison.Ordinal))
                {
                    continue;
                }

                relatives.Add(relative);
            }

            if (_canonicalApp0IndexV74042)
            {
                foreach (var candidateSet in _canonicalCollisionCandidatesV74042.Values)
                {
                    foreach (var collisionHostPath in candidateSet.Keys)
                    {
                        var relative = Path.GetRelativePath(
                                normalizedRoot,
                                collisionHostPath)
                            .Replace('\\', '/');
                        if (string.IsNullOrEmpty(relative) ||
                            relative.StartsWith("..", StringComparison.Ordinal))
                        {
                            continue;
                        }

                        relatives.Add(relative);
                    }
                }
            }

            var tempPath = cachePath + ".tmp";
            using (var stream = File.Create(tempPath))
            using (var writer = new BinaryWriter(stream, Encoding.UTF8, leaveOpen: false))
            {
                writer.Write(CacheMagicV3);
                writer.Write(CacheVersionV3);
                writer.Write(normalizedRoot);
                writer.Write(relatives.Count);
                writer.Write(paramTicks);
                foreach (var relative in relatives)
                {
                    writer.Write(relative);
                    // Mirror RegisterApp0Relative id order: $/ /app0/ app0/ bare.
                    writer.Write(ComputeApp0AliasIds(relative, out var id1, out var id2, out var id3));
                    writer.Write(id1);
                    writer.Write(id2);
                    writer.Write(id3);
                }
            }

            File.Move(tempPath, cachePath, overwrite: true);
            Console.Error.WriteLine(
                $"[LOADER][INFO] ampr.app0_index_cache_saved path={cachePath} " +
                $"files={relatives.Count}");
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] ampr.app0_index_cache_save_failed: {exception.Message}");
        }
    }

    private static uint ComputeApp0AliasIds(
        string relative,
        out uint app0Slash,
        out uint app0,
        out uint bare)
    {
        var dollar = FnvContinueUtf8(
            FnvContinueAscii(FnvContinueAscii(OffsetBasis, (byte)'$'), (byte)'/'),
            relative);
        app0Slash = FnvContinueUtf8(FnvContinueAsciiPrefix(OffsetBasis, "/app0/"u8), relative);
        app0 = FnvContinueUtf8(FnvContinueAsciiPrefix(OffsetBasis, "app0/"u8), relative);
        bare = FnvContinueUtf8(OffsetBasis, relative);
        return dollar;
    }

    /// <summary>
    /// Cheap dump fingerprint. Full-tree walks are too expensive for cache
    /// validation; param.json changes with title updates. Force a rebuild with
    /// SHARPEMU_AMPR_REINDEX=1 after manual dump edits.
    /// </summary>
    private static long GetParamJsonWriteTicks(string normalizedRoot)
    {
        try
        {
            var paramPath = Path.Combine(normalizedRoot, "sce_sys", "param.json");
            return File.Exists(paramPath)
                ? File.GetLastWriteTimeUtc(paramPath).Ticks
                : 0;
        }
        catch
        {
            return 0;
        }
    }

    private const uint OffsetBasis = 2166136261;
    private const uint FnvPrime = 16777619;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static uint FnvContinueAscii(uint hash, byte value)
    {
        hash ^= value;
        return hash * FnvPrime;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static uint FnvContinueAsciiPrefix(uint hash, ReadOnlySpan<byte> ascii)
    {
        foreach (var value in ascii)
        {
            hash ^= value;
            hash *= FnvPrime;
        }

        return hash;
    }

    private static uint FnvContinueUtf8(uint hash, string text)
    {
        // Game asset paths are overwhelmingly ASCII; avoid Encoding.GetBytes
        // allocations on the 223k-file DeS index hot path.
        Span<byte> utf8Scratch = stackalloc byte[4];
        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];
            if (ch < 0x80)
            {
                hash ^= (byte)ch;
                hash *= FnvPrime;
                continue;
            }

            var written = Encoding.UTF8.GetBytes(text.AsSpan(i, 1), utf8Scratch);
            for (var b = 0; b < written; b++)
            {
                hash ^= utf8Scratch[b];
                hash *= FnvPrime;
            }
        }

        return hash;
    }
}
