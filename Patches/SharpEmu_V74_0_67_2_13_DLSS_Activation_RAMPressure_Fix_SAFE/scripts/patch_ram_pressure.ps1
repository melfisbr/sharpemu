. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))

if($a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')){
    Write-Host '[V74.0.67.2.13] Large-array RAM patch already applied.'
    return
}

function Replace-One {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Old,
        [Parameter(Mandatory=$true)][string]$New,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $count=Count-Ordinal -Text $Text -Needle $Old
    if($count-ne 1){throw "[V74.0.67.2.13] RAM anchor '$Label' count=$count expected=1"}
    return $Text.Replace($Old,$New)
}

if(!$a.Contains('V74015LargeArraySnapshotKey') -or !$a.Contains('[V74.0.15][ARRAY_SINGLEFLIGHT]')){
    throw '[V74.0.67.2.13] V74.0.15 large-array single-flight source is required.'
}

$a=Replace-One $a '        long WriteGeneration,' '        ulong ContentKey,' 'large-array key field'

$traceField='    private static int _v74015LargeArraySnapshotReuseTraceCount;'
$traceInsert=@'
    private static int _v74015LargeArraySnapshotReuseTraceCount;

    // V74.0.67.2.13 large-array sparse-content reuse key
    private static long _v74067213LargeArrayProbeFailureNonce;
    private const long V74067213MinimumArrayReuseTtlMs = 60000L;
'@
$a=Replace-One $a $traceField $traceInsert 'large-array probe fields'

$helperAnchor='    private static void TraceTextureFallback(TextureDescriptor descriptor, string reason)'
$helper=@'
    private static ulong ComputeV74067213LargeArrayContentKey(
        CpuContext ctx,
        ulong baseAddress,
        uint layers,
        ulong guestLayerStride,
        ulong readableSliceBytes,
        long writeGeneration)
    {
        if (SharpEmu.HLE.GuestImageWriteTracker.Enabled &&
            writeGeneration >= 0)
        {
            return 0xD15A000000000000UL ^
                   unchecked((ulong)writeGeneration);
        }

        if (layers == 0 || readableSliceBytes == 0)
        {
            return 0;
        }

        const int SampleBytes = 64;
        const int SampleCount = 32;
        Span<byte> sample = stackalloc byte[SampleBytes];
        ulong hash = 14695981039346656037UL;
        ulong packedBytes;
        try
        {
            packedBytes = checked(readableSliceBytes * layers);
        }
        catch (OverflowException)
        {
            return unchecked((ulong)Interlocked.Increment(
                ref _v74067213LargeArrayProbeFailureNonce));
        }

        var maximumOffset = packedBytes > SampleBytes
            ? packedBytes - SampleBytes
            : 0UL;

        for (var sampleIndex = 0; sampleIndex < SampleCount; sampleIndex++)
        {
            var packedOffset = maximumOffset * (ulong)sampleIndex /
                (ulong)(SampleCount - 1);
            var layer = packedOffset / readableSliceBytes;
            var within = packedOffset % readableSliceBytes;
            if (within + SampleBytes > readableSliceBytes)
            {
                within = readableSliceBytes > SampleBytes
                    ? readableSliceBytes - SampleBytes
                    : 0UL;
            }

            var guestAddress =
                baseAddress + layer * guestLayerStride + within;
            var readLength = (int)Math.Min(
                (ulong)SampleBytes,
                readableSliceBytes - within);
            var destination = sample[..readLength];

            if (!TryReadTextureGuestMemory(ctx, guestAddress, destination))
            {
                var nonce = Interlocked.Increment(
                    ref _v74067213LargeArrayProbeFailureNonce);
                return 0xBAD0000000000000UL ^
                       unchecked((ulong)nonce);
            }

            for (var i = 0; i < destination.Length; i++)
            {
                hash ^= destination[i];
                hash *= 1099511628211UL;
            }

            hash ^= layer;
            hash *= 1099511628211UL;
        }

        return hash;
    }

    private static long V74067213EffectiveArrayReuseTtlMs(long configuredTtlMs)
    {
        var configured = Environment.GetEnvironmentVariable(
            "SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS");
        if (long.TryParse(configured, out var requested) && requested > 0)
        {
            return Math.Clamp(requested, 1000L, 120000L);
        }

        return Math.Max(configuredTtlMs, V74067213MinimumArrayReuseTtlMs);
    }

    private static void TraceTextureFallback(TextureDescriptor descriptor, string reason)
'@
$a=Replace-One $a $helperAnchor $helper 'content-probe helper'

$oldTiled=@'
                            sourceWidth,
                            sliceBytes,
                            arrayLayers,
                            hasWriteGeneration ? writeGeneration : -1,
                            Tiled: true);
'@
$newTiled=@'
                            sourceWidth,
                            sliceBytes,
                            arrayLayers,
                            ComputeV74067213LargeArrayContentKey(
                                ctx,
                                descriptor.Address + baseMipByteOffset,
                                arrayLayers,
                                chainSliceBytes,
                                (ulong)sliceBytes,
                                hasWriteGeneration ? writeGeneration : -1),
                            Tiled: true);
'@
$a=Replace-One $a $oldTiled $newTiled 'tiled content key'

$oldLinear=@'
                        sourceWidth,
                        layerBytes,
                        arrayLayers,
                        hasWriteGeneration ? writeGeneration : -1,
                        Tiled: false);
'@
$newLinear=@'
                        sourceWidth,
                        layerBytes,
                        arrayLayers,
                        ComputeV74067213LargeArrayContentKey(
                            ctx,
                            descriptor.Address + baseMipByteOffset,
                            arrayLayers,
                            chainSliceBytes,
                            chainSliceBytes,
                            hasWriteGeneration ? writeGeneration : -1),
                        Tiled: false);
'@
$a=Replace-One $a $oldLinear $newLinear 'linear content key'

$ttlPattern='v74015Age\s*<=\s*([A-Za-z_][A-Za-z0-9_]*)'
$ttlMatches=[regex]::Matches($a,$ttlPattern)
if($ttlMatches.Count-lt 2){throw "[V74.0.67.2.13] Expected >=2 v74015Age TTL comparisons; got $($ttlMatches.Count)"}
$a=[regex]::Replace($a,$ttlPattern,'v74015Age <= V74067213EffectiveArrayReuseTtlMs($1)')

[IO.File]::WriteAllText($agcPath,(Restore-Newlines $a),[Text.UTF8Encoding]::new($false))
Write-Host "[V74.0.67.2.13] LARGE-ARRAY RAM PRESSURE PATCH APPLIED. ttl_comparisons=$($ttlMatches.Count)"
