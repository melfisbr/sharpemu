param(
    [Parameter(Mandatory=$true)][string]$PresenterPath,
    [Parameter(Mandatory=$true)][string]$AgcPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Replace-OneExact {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Old,
        [Parameter(Mandatory=$true)][string]$New,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $first=$Text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){
        throw "${Label} anchor not found."
    }
    $second=$Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){
        throw "${Label} anchor duplicated."
    }
    return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}

if(-not [IO.File]::Exists($PresenterPath)){throw "Presenter missing: $PresenterPath"}
if(-not [IO.File]::Exists($AgcPath)){throw "Agc missing: $AgcPath"}

$presenter=[IO.File]::ReadAllText($PresenterPath)
$agc=[IO.File]::ReadAllText($AgcPath)
$presenterChanged=$false
$agcChanged=$false

$fieldsOld=@'
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<
        TextureContentIdentity, byte> _cachedTextureIdentities = new();

'@
$fieldsNew=@'
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<
        TextureContentIdentity, byte> _cachedTextureIdentities = new();

    // SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19
    // When GuestImageWriteTracker is disabled (the Windows default in this
    // checkout), cached tiled/UI textures still need a cheap content signal.
    private readonly record struct UntrackedTextureCacheProbe(
        ulong Hash,
        ulong ByteCount);
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<
        TextureContentIdentity, UntrackedTextureCacheProbe>
        _untrackedTextureCacheProbes = new();
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<
        TextureContentIdentity, byte> _staleTextureIdentities = new();
    private static long _v73019TextureCacheStaleTraceCount;
    private static long _v73019TextureCacheRefreshTraceCount;

'@
$methodsOld=@'
    internal static bool IsTextureContentCached(in TextureContentIdentity identity) =>
        _cachedTextureIdentities.ContainsKey(identity);

    private static void MarkTextureContentCached(in TextureContentIdentity identity) =>
        _cachedTextureIdentities.TryAdd(identity, 0);

    private static void UnmarkTextureContentCached(in TextureContentIdentity identity) =>
        _cachedTextureIdentities.TryRemove(identity, out _);

    private static void ClearCachedTextureIdentities() =>
        _cachedTextureIdentities.Clear();

'@
$methodsNew=@'
    private static bool ShouldProbeUntrackedTextureCache() =>
        !SharpEmu.HLE.GuestImageWriteTracker.Enabled &&
        SharpEmu.Libs.Kernel.KernelMemoryCompatExports.IsConfiguredApplicationTitle(
            "PPSA01341");

    internal static bool IsTextureContentCached(in TextureContentIdentity identity)
    {
        if (!_cachedTextureIdentities.ContainsKey(identity))
        {
            return false;
        }

        if (!ShouldProbeUntrackedTextureCache() || identity.Address == 0)
        {
            return true;
        }

        if (!_untrackedTextureCacheProbes.TryGetValue(identity, out var previous))
        {
            _cachedTextureIdentities.TryRemove(identity, out _);
            _staleTextureIdentities.TryAdd(identity, 0);
            TraceUntrackedTextureCacheStale(
                identity,
                0,
                0,
                "missing-baseline");
            return false;
        }

        var memory = _guestMemory;
        if (memory is null || previous.ByteCount == 0)
        {
            return true;
        }

        var current = ComputeSparseGuestContentProbe(
            memory,
            identity.Address,
            previous.ByteCount);
        if (current == previous.Hash)
        {
            return true;
        }

        _cachedTextureIdentities.TryRemove(identity, out _);
        _untrackedTextureCacheProbes.TryRemove(identity, out _);
        _staleTextureIdentities.TryAdd(identity, 0);
        TraceUntrackedTextureCacheStale(
            identity,
            previous.Hash,
            current,
            "guest-bytes-changed");
        return false;
    }

    private static void MarkTextureContentCached(
        in TextureContentIdentity identity,
        GuestDrawTexture texture)
    {
        _cachedTextureIdentities.TryAdd(identity, 0);
        _staleTextureIdentities.TryRemove(identity, out _);

        if (!ShouldProbeUntrackedTextureCache() ||
            identity.Address == 0 ||
            !TryBuildUntrackedTextureProbe(
                texture,
                GetTextureContentProbeByteCount(identity),
                out var probe))
        {
            _untrackedTextureCacheProbes.TryRemove(identity, out _);
            return;
        }

        _untrackedTextureCacheProbes[identity] = probe;
    }

    private static void UnmarkTextureContentCached(in TextureContentIdentity identity)
    {
        _cachedTextureIdentities.TryRemove(identity, out _);
        _untrackedTextureCacheProbes.TryRemove(identity, out _);
        _staleTextureIdentities.TryRemove(identity, out _);
    }

    private static void ClearCachedTextureIdentities()
    {
        _cachedTextureIdentities.Clear();
        _untrackedTextureCacheProbes.Clear();
        _staleTextureIdentities.Clear();
    }

    private static ulong GetTextureContentProbeByteCount(
        in TextureContentIdentity identity)
    {
        var rowLength = identity.TileMode == 0
            ? Math.Max(identity.Pitch, identity.Width)
            : identity.Width;
        var depth = GetGuestTextureDepth(identity.Type, identity.Depth);
        var layers = identity.Arrayed
            ? Math.Max(identity.ArrayLayers, 1u)
            : 1u;

        try
        {
            var perLayerOrVolume = GetGuestImageByteCount(
                identity.Format,
                rowLength,
                identity.Height,
                depth);
            return checked(perLayerOrVolume * layers);
        }
        catch (OverflowException)
        {
            return 0;
        }
    }

    private static bool TryBuildUntrackedTextureProbe(
        GuestDrawTexture texture,
        ulong byteCount,
        out UntrackedTextureCacheProbe probe)
    {
        probe = default;
        if (texture.Address == 0 ||
            byteCount == 0 ||
            byteCount > MaxTrackedGuestImageBytes)
        {
            return false;
        }

        if (texture.TileMode == 0 &&
            texture.RgbaPixels.LongLength >= (long)byteCount &&
            byteCount <= int.MaxValue)
        {
            probe = new UntrackedTextureCacheProbe(
                ComputeSparseSubmittedContentProbe(
                    texture.RgbaPixels.AsSpan(0, (int)byteCount)),
                byteCount);
            return true;
        }

        if (!texture.ArrayedView &&
            texture.TiledSource is { Length: > 0 } tiled &&
            tiled.LongLength >= (long)byteCount &&
            byteCount <= int.MaxValue)
        {
            probe = new UntrackedTextureCacheProbe(
                ComputeSparseSubmittedContentProbe(
                    tiled.AsSpan(0, (int)byteCount)),
                byteCount);
            return true;
        }

        var memory = _guestMemory;
        if (memory is null)
        {
            return false;
        }

        probe = new UntrackedTextureCacheProbe(
            ComputeSparseGuestContentProbe(
                memory,
                texture.Address,
                byteCount),
            byteCount);
        return true;
    }

    private static ulong ComputeSparseSubmittedContentProbe(
        ReadOnlySpan<byte> content)
    {
        ulong hash = 14695981039346656037UL;
        if (content.IsEmpty)
        {
            return hash;
        }

        const int SampleBytes = 64;
        Span<int> offsets = stackalloc int[8];
        var offsetCount = content.Length <= SampleBytes
            ? 1
            : offsets.Length;
        var maximumOffset = Math.Max(content.Length - SampleBytes, 0);

        if (offsetCount == 1)
        {
            offsets[0] = 0;
        }
        else
        {
            for (var index = 0; index < offsetCount; index++)
            {
                offsets[index] =
                    maximumOffset * index / (offsetCount - 1);
            }
        }

        for (var index = 0; index < offsetCount; index++)
        {
            var offset = offsets[index];
            var length = Math.Min(SampleBytes, content.Length - offset);
            var sample = content.Slice(offset, length);
            for (var byteIndex = 0; byteIndex < sample.Length; byteIndex++)
            {
                hash ^= sample[byteIndex];
                hash *= 1099511628211UL;
            }

            hash ^= (ulong)length + (ulong)offset;
        }

        return hash ^ (ulong)content.Length;
    }

    private static void TraceUntrackedTextureCacheStale(
        in TextureContentIdentity identity,
        ulong previous,
        ulong current,
        string reason)
    {
        var count = Interlocked.Increment(
            ref _v73019TextureCacheStaleTraceCount);
        if (count > 64 && (count & (count - 1)) != 0)
        {
            return;
        }

        Console.Error.WriteLine(
            $"[V73.0.19][TEXTURE_CACHE_STALE] count={count} " +
            $"reason={reason} addr=0x{identity.Address:X16} " +
            $"size={identity.Width}x{identity.Height} " +
            $"fmt={identity.Format}/{identity.NumberType} " +
            $"tile={identity.TileMode} array={(identity.Arrayed ? 1 : 0)} " +
            $"old=0x{previous:X16} new=0x{current:X16}");
    }

'@
$readOld=@'
            if (!memory.TryRead(address + offset, sample[..length]))
            {
                hash ^= 0x9E3779B97F4A7C15UL + offset;
                continue;
            }

'@
$readNew=@'
            if (!TryReadGuestTextureBacking(
                    memory,
                    address + offset,
                    sample[..length]))
            {
                hash ^= 0x9E3779B97F4A7C15UL + offset;
                continue;
            }

'@
$computeOld=@'
    private static ulong ComputeSparseGuestContentProbe(
        SharpEmu.HLE.ICpuMemory memory,
        ulong address,
        ulong byteCount)

'@
$computeNew=@'
    private static bool TryReadGuestTextureBacking(
        SharpEmu.HLE.ICpuMemory memory,
        ulong address,
        Span<byte> destination) =>
        memory.TryRead(address, destination) ||
        SharpEmu.Libs.Kernel.KernelMemoryCompatExports.TryReadTrackedLibcHeap(
            address,
            destination) ||
        SharpEmu.Libs.Kernel.KernelMemoryCompatExports.TryReadTrackedLibcHeapGpuAlias(
            address,
            destination);

    private static ulong ComputeSparseGuestContentProbe(
        SharpEmu.HLE.ICpuMemory memory,
        ulong address,
        ulong byteCount)

'@
$selfHealOld=@'
            var pixels = new byte[(int)byteCount];
            return memory.TryRead(texture.Address, pixels) ? pixels : null;

'@
$selfHealNew=@'
            var pixels = new byte[(int)byteCount];
            return TryReadGuestTextureBacking(
                    memory,
                    texture.Address,
                    pixels)
                ? pixels
                : null;

'@
$cacheHitOld=@'
            if (_textureCache.TryGetValue(key, out var cached))
            {
                return cached;
            }

'@
$cacheHitNew=@'
            if (_textureCache.TryGetValue(key, out var cached))
            {
                if (!_staleTextureIdentities.TryRemove(key, out _))
                {
                    return cached;
                }

                if (_batchOpen)
                {
                    FlushBatchedGuestCommands();
                }

                if (_textureCache.Remove(key, out var staleResource))
                {
                    UnmarkTextureContentCached(key);
                    _deferredTextureDestroys.Enqueue(
                        (staleResource, _submitTimeline));

                    var refreshCount = Interlocked.Increment(
                        ref _v73019TextureCacheRefreshTraceCount);
                    if (refreshCount <= 64 ||
                        (refreshCount & (refreshCount - 1)) == 0)
                    {
                        Console.Error.WriteLine(
                            $"[V73.0.19][TEXTURE_CACHE_REFRESH] " +
                            $"count={refreshCount} " +
                            $"addr=0x{key.Address:X16} " +
                            $"size={key.Width}x{key.Height} " +
                            $"fmt={key.Format}/{key.NumberType} " +
                            $"tile={key.TileMode}");
                    }
                }
            }

'@
$extentOld=@'
                    _guestImageExtents[texture.Address] =
                        (width, height, expectedSize);
                }

'@
$extentNew=@'
                    _guestImageExtents[texture.Address] =
                        (width, height, expectedSize);

                    if (ShouldProbeUntrackedTextureCache() &&
                        TryBuildUntrackedTextureProbe(
                            texture,
                            expectedSize,
                            out var initialProbe))
                    {
                        _untrackedGuestImageContentProbes[texture.Address] =
                            initialProbe.Hash;
                    }
                }

'@
$agcOld=@'
        var readOk = ctx.Memory.TryRead(target.Address, initialData);
'@
$agcNew=@'
        // SHARPEMU_DEMONSSOULS_UI_RT_ALIAS_READ_V73_0_19
        // CPU-prefilled UI/font render targets can live in tracked libc memory
        // or through the packed low-46-bit GPU alias used by Gen5 descriptors.
        var readOk = TryReadTextureGuestMemory(
            ctx,
            target.Address,
            initialData);
'@

if(-not $presenter.Contains('SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19')){
    $presenter=Replace-OneExact $presenter $fieldsOld $fieldsNew 'cache-fields'
    $presenter=Replace-OneExact $presenter $methodsOld $methodsNew 'cache-methods'
    $presenter=Replace-OneExact $presenter $readOld $readNew 'sparse-read'
    $presenter=Replace-OneExact $presenter $computeOld $computeNew 'alias-read-helper'
    $presenter=Replace-OneExact $presenter $selfHealOld $selfHealNew 'self-heal-read'
    $presenter=Replace-OneExact $presenter $cacheHitOld $cacheHitNew 'render-cache-refresh'
    $presenter=Replace-OneExact $presenter $extentOld $extentNew 'guest-image-probe-seed'

    $markOld='MarkTextureContentCached(key);'
    $markNew='MarkTextureContentCached(key, texture);'
    $markFirst=$presenter.IndexOf($markOld,[StringComparison]::Ordinal)
    if($markFirst -lt 0){throw 'MarkTextureContentCached call anchor not found.'}
    $markSecond=$presenter.IndexOf($markOld,$markFirst+$markOld.Length,[StringComparison]::Ordinal)
    if($markSecond -ge 0){throw 'MarkTextureContentCached call anchor duplicated.'}
    $presenter=$presenter.Substring(0,$markFirst)+$markNew+$presenter.Substring($markFirst+$markOld.Length)
    $presenterChanged=$true
}

if(-not $agc.Contains('SHARPEMU_DEMONSSOULS_UI_RT_ALIAS_READ_V73_0_19')){
    $agc=Replace-OneExact $agc $agcOld $agcNew 'rt-initial-alias-read'
    $agcChanged=$true
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19',
    '[V73.0.19][TEXTURE_CACHE_STALE]',
    '[V73.0.19][TEXTURE_CACHE_REFRESH]',
    'TryReadGuestTextureBacking',
    'MarkTextureContentCached(key, texture)'
)){
    if(-not $presenter.Contains($marker)){throw "Presenter marker missing: $marker"}
}
if(-not $agc.Contains('SHARPEMU_DEMONSSOULS_UI_RT_ALIAS_READ_V73_0_19')){
    throw 'AGC UI alias-read marker missing.'
}

if($presenterChanged){
    [IO.File]::WriteAllText($PresenterPath,$presenter,[Text.UTF8Encoding]::new($false))
}
if($agcChanged){
    [IO.File]::WriteAllText($AgcPath,$agc,[Text.UTF8Encoding]::new($false))
}

Write-Host "[V73.0.19] structural patch presenter_changed=$presenterChanged agc_changed=$agcChanged" -ForegroundColor Green
