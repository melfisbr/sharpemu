param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74015 $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$agc=Get-AgcPathV74015 $root
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot=[System.IO.Path]::Combine($root,".sharpemu-hotfix-backup","LargeArraySingleFlight_V74_0_15_$stamp")
[System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
$backupAgc=[System.IO.Path]::Combine($backupRoot,"AgcExports.cs")
Copy-Item -LiteralPath $agc -Destination $backupAgc -Force
$sourceChanged=$false

function Replace-UniqueLiteralV74015 {
    param([string]$Text,[string]$Old,[string]$New,[string]$Description)
    $normalizedOld=$Old.Replace("`r`n","`n")
    $normalizedNew=$New.Replace("`r`n","`n")
    $first=$Text.IndexOf($normalizedOld,[System.StringComparison]::Ordinal)
    if($first -lt 0){ throw "[V74.0.15] $Description target not found." }
    $second=$Text.IndexOf($normalizedOld,$first+$normalizedOld.Length,[System.StringComparison]::Ordinal)
    if($second -ge 0){ throw "[V74.0.15] $Description target is not unique." }
    return $Text.Substring(0,$first)+$normalizedNew+$Text.Substring($first+$normalizedOld.Length)
}

try{
    $text=[System.IO.File]::ReadAllText($agc)
    $sourceUsesCrLf=$text.Contains("`r`n")
    $text=$text.Replace("`r`n","`n")
    if(-not $text.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT")){

        $fieldAnchor="private static int _v7405LargeTextureSnapshotReuseTraceCount;"
        $fieldBlock=@'
private static int _v7405LargeTextureSnapshotReuseTraceCount;

    // SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT
    // Large array uploads can be requested concurrently before the backend's
    // texture cache becomes visible. Keep one exact immutable byte snapshot
    // briefly so concurrent callers share the same 320MB-class payload instead
    // of allocating/copying it repeatedly. This does not skip layers or alter
    // texture contents.
    private readonly record struct V74015LargeArraySnapshotKey(
        ulong Address,
        uint Width,
        uint Height,
        uint Format,
        uint NumberType,
        uint TileMode,
        uint Pitch,
        int SliceBytes,
        uint ArrayLayers,
        long WriteGeneration,
        bool Tiled);

    private const long V74015LargeArrayThresholdBytes = 64L * 1024L * 1024L;
    private const long V74015LargeArraySnapshotTtlMs = 500L;
    private static readonly object _v74015LargeArraySnapshotGate = new();
    private static V74015LargeArraySnapshotKey _v74015LargeArraySnapshotKey;
    private static byte[]? _v74015LargeArraySnapshotData;
    private static long _v74015LargeArraySnapshotTick;
    private static bool _v74015LargeArraySnapshotValid;
    private static long _v74015LargeArraySnapshotReuseBytes;
    private static int _v74015LargeArraySnapshotOwnerTraceCount;
    private static int _v74015LargeArraySnapshotReuseTraceCount;
'@
        $text=Replace-UniqueLiteralV74015 -Text $text -Old $fieldAnchor -New $fieldBlock -Description "large-array field insertion"

        # Bound the older V74.0.5 non-array transient cache. It was designed for
        # the measured 15MB surfaces; V74.0.15 owns >=64MB array coalescing.
        $v7405Old=@'
        var v7405CacheLargeSnapshot =
            !isStorage &&
            descriptor.MetadataAddress == 0 &&
            descriptor.Address != 0 &&
            physicalSourceByteCount >= 8UL * 1024UL * 1024UL;
'@
        $v7405New=@'
        var v7405CacheLargeSnapshot =
            !isStorage &&
            descriptor.MetadataAddress == 0 &&
            descriptor.Address != 0 &&
            physicalSourceByteCount >= 8UL * 1024UL * 1024UL &&
            physicalSourceByteCount <= 32UL * 1024UL * 1024UL;
'@
        $v7405Old=$v7405Old.Replace("`r`n","`n")
        $v7405New=$v7405New.Replace("`r`n","`n")
        if($text.Contains($v7405Old)){
            $text=Replace-UniqueLiteralV74015 -Text $text -Old $v7405Old -New $v7405New -Description "V74.0.5 snapshot upper bound"
        }
        elseif(-not $text.Contains($v7405New)){
            throw "[V74.0.15] V74.0.5 snapshot predicate is neither original nor V74.0.15-bounded."
        }

        $gpuOld=@'
                    var sliceBytes = checked((int)physicalSourceByteCount);
                    var tiledLayers = new byte[(long)sliceBytes * arrayLayers];
                    var readAllLayers = true;
                    for (var layer = 0u; layer < arrayLayers; layer++)
                    {
                        if (!TryReadTextureGuestMemory(ctx,
                                descriptor.Address + layer * chainSliceBytes + baseMipByteOffset,
                                tiledLayers.AsSpan(checked((int)(layer * (uint)sliceBytes)), sliceBytes)))
                        {
                            readAllLayers = false;
                            break;
                        }
                    }
'@
        $gpuNew=@'
                    var sliceBytes = checked((int)physicalSourceByteCount);
                    var totalTiledArrayBytes = checked((long)sliceBytes * arrayLayers);
                    byte[] tiledLayers;
                    var readAllLayers = true;

                    if (totalTiledArrayBytes >= V74015LargeArrayThresholdBytes)
                    {
                        var v74015ArrayKey = new V74015LargeArraySnapshotKey(
                            descriptor.Address,
                            descriptor.Width,
                            descriptor.Height,
                            descriptor.Format,
                            descriptor.NumberType,
                            descriptor.TileMode,
                            sourceWidth,
                            sliceBytes,
                            arrayLayers,
                            hasWriteGeneration ? writeGeneration : -1,
                            Tiled: true);

                        lock (_v74015LargeArraySnapshotGate)
                        {
                            var v74015Now = Environment.TickCount64;
                            var v74015Age = unchecked(v74015Now - _v74015LargeArraySnapshotTick);
                            if (_v74015LargeArraySnapshotValid &&
                                v74015ArrayKey.Equals(_v74015LargeArraySnapshotKey) &&
                                v74015Age >= 0 &&
                                v74015Age <= V74015LargeArraySnapshotTtlMs &&
                                _v74015LargeArraySnapshotData is { } v74015Cached &&
                                v74015Cached.LongLength == totalTiledArrayBytes)
                            {
                                tiledLayers = v74015Cached;
                                var reuseBytes = Interlocked.Add(
                                    ref _v74015LargeArraySnapshotReuseBytes,
                                    totalTiledArrayBytes);
                                var reuseCount = Interlocked.Increment(
                                    ref _v74015LargeArraySnapshotReuseTraceCount);
                                if (reuseCount <= 32 || reuseCount % 128 == 0)
                                {
                                    Console.Error.WriteLine(
                                        $"[V74.0.15][ARRAY_SINGLEFLIGHT] reuse path=tiled " +
                                        $"count={reuseCount} addr=0x{descriptor.Address:X16} " +
                                        $"size={descriptor.Width}x{descriptor.Height} layers={arrayLayers} " +
                                        $"bytes={totalTiledArrayBytes} saved_mb={reuseBytes / (1024 * 1024)}");
                                }
                            }
                            else
                            {
                                tiledLayers = GC.AllocateUninitializedArray<byte>(
                                    checked((int)totalTiledArrayBytes));
                                for (var layer = 0u; layer < arrayLayers; layer++)
                                {
                                    if (!TryReadTextureGuestMemory(ctx,
                                            descriptor.Address + layer * chainSliceBytes + baseMipByteOffset,
                                            tiledLayers.AsSpan(
                                                checked((int)(layer * (uint)sliceBytes)),
                                                sliceBytes)))
                                    {
                                        readAllLayers = false;
                                        break;
                                    }
                                }

                                if (readAllLayers)
                                {
                                    _v74015LargeArraySnapshotKey = v74015ArrayKey;
                                    _v74015LargeArraySnapshotData = tiledLayers;
                                    _v74015LargeArraySnapshotTick = Environment.TickCount64;
                                    _v74015LargeArraySnapshotValid = true;
                                    var ownerCount = Interlocked.Increment(
                                        ref _v74015LargeArraySnapshotOwnerTraceCount);
                                    if (ownerCount <= 16 || ownerCount % 64 == 0)
                                    {
                                        Console.Error.WriteLine(
                                            $"[V74.0.15][ARRAY_SINGLEFLIGHT] owner path=tiled " +
                                            $"count={ownerCount} addr=0x{descriptor.Address:X16} " +
                                            $"size={descriptor.Width}x{descriptor.Height} layers={arrayLayers} " +
                                            $"bytes={totalTiledArrayBytes}");
                                    }
                                }
                            }
                        }
                    }
                    else
                    {
                        tiledLayers = GC.AllocateUninitializedArray<byte>(
                            checked((int)totalTiledArrayBytes));
                        for (var layer = 0u; layer < arrayLayers; layer++)
                        {
                            if (!TryReadTextureGuestMemory(ctx,
                                    descriptor.Address + layer * chainSliceBytes + baseMipByteOffset,
                                    tiledLayers.AsSpan(
                                        checked((int)(layer * (uint)sliceBytes)),
                                        sliceBytes)))
                            {
                                readAllLayers = false;
                                break;
                            }
                        }
                    }
'@
        $text=Replace-UniqueLiteralV74015 -Text $text -Old $gpuOld -New $gpuNew -Description "GPU tiled array single-flight"

        $cpuOld=@'
            if (totalBytes <= int.MaxValue)
            {
                var layered = new byte[totalBytes];
                var uploadedLayers = 0u;
                for (var layer = 0u; layer < arrayLayers; layer++)
                {
                    var sliceSource = new byte[(int)chainSliceBytes];
                    if (!TryReadTextureGuestMemory(ctx,
                            descriptor.Address + layer * chainSliceBytes + baseMipByteOffset,
                            sliceSource))
                    {
                        break;
                    }

                    var sliceLinear = TryDetileTextureSource(
                        descriptor,
                        sourceWidth,
                        layerBytes,
                        sliceSource,
                        baseMipInTail,
                        mipTailElementX,
                        mipTailElementY) ?? sliceSource.AsSpan(0, layerBytes).ToArray();
                    sliceLinear.AsSpan(0, layerBytes)
                        .CopyTo(layered.AsSpan(checked((int)(layer * layerBytes))));
                    uploadedLayers++;
                }

                if (uploadedLayers == arrayLayers)
'@
        $cpuNew=@'
            if (totalBytes <= int.MaxValue)
            {
                byte[] layered;
                var uploadedLayers = 0u;

                if (totalBytes >= V74015LargeArrayThresholdBytes)
                {
                    var v74015ArrayKey = new V74015LargeArraySnapshotKey(
                        descriptor.Address,
                        descriptor.Width,
                        descriptor.Height,
                        descriptor.Format,
                        descriptor.NumberType,
                        descriptor.TileMode,
                        sourceWidth,
                        layerBytes,
                        arrayLayers,
                        hasWriteGeneration ? writeGeneration : -1,
                        Tiled: false);

                    lock (_v74015LargeArraySnapshotGate)
                    {
                        var v74015Now = Environment.TickCount64;
                        var v74015Age = unchecked(v74015Now - _v74015LargeArraySnapshotTick);
                        if (_v74015LargeArraySnapshotValid &&
                            v74015ArrayKey.Equals(_v74015LargeArraySnapshotKey) &&
                            v74015Age >= 0 &&
                            v74015Age <= V74015LargeArraySnapshotTtlMs &&
                            _v74015LargeArraySnapshotData is { } v74015Cached &&
                            v74015Cached.LongLength == totalBytes)
                        {
                            layered = v74015Cached;
                            uploadedLayers = arrayLayers;
                            var reuseBytes = Interlocked.Add(
                                ref _v74015LargeArraySnapshotReuseBytes,
                                totalBytes);
                            var reuseCount = Interlocked.Increment(
                                ref _v74015LargeArraySnapshotReuseTraceCount);
                            if (reuseCount <= 32 || reuseCount % 128 == 0)
                            {
                                Console.Error.WriteLine(
                                    $"[V74.0.15][ARRAY_SINGLEFLIGHT] reuse path=linear " +
                                    $"count={reuseCount} addr=0x{descriptor.Address:X16} " +
                                    $"size={descriptor.Width}x{descriptor.Height} layers={arrayLayers} " +
                                    $"bytes={totalBytes} saved_mb={reuseBytes / (1024 * 1024)}");
                            }
                        }
                        else
                        {
                            layered = GC.AllocateUninitializedArray<byte>(checked((int)totalBytes));
                            var sliceSource = GC.AllocateUninitializedArray<byte>(
                                checked((int)chainSliceBytes));
                            for (var layer = 0u; layer < arrayLayers; layer++)
                            {
                                if (!TryReadTextureGuestMemory(ctx,
                                        descriptor.Address + layer * chainSliceBytes + baseMipByteOffset,
                                        sliceSource))
                                {
                                    break;
                                }

                                var sliceLinear = TryDetileTextureSource(
                                    descriptor,
                                    sourceWidth,
                                    layerBytes,
                                    sliceSource,
                                    baseMipInTail,
                                    mipTailElementX,
                                    mipTailElementY) ?? sliceSource.AsSpan(0, layerBytes).ToArray();
                                sliceLinear.AsSpan(0, layerBytes)
                                    .CopyTo(layered.AsSpan(checked((int)(layer * layerBytes))));
                                uploadedLayers++;
                            }

                            if (uploadedLayers == arrayLayers)
                            {
                                _v74015LargeArraySnapshotKey = v74015ArrayKey;
                                _v74015LargeArraySnapshotData = layered;
                                _v74015LargeArraySnapshotTick = Environment.TickCount64;
                                _v74015LargeArraySnapshotValid = true;
                                var ownerCount = Interlocked.Increment(
                                    ref _v74015LargeArraySnapshotOwnerTraceCount);
                                if (ownerCount <= 16 || ownerCount % 64 == 0)
                                {
                                    Console.Error.WriteLine(
                                        $"[V74.0.15][ARRAY_SINGLEFLIGHT] owner path=linear " +
                                        $"count={ownerCount} addr=0x{descriptor.Address:X16} " +
                                        $"size={descriptor.Width}x{descriptor.Height} layers={arrayLayers} " +
                                        $"bytes={totalBytes}");
                                }
                            }
                        }
                    }
                }
                else
                {
                    layered = new byte[checked((int)totalBytes)];
                    for (var layer = 0u; layer < arrayLayers; layer++)
                    {
                        var sliceSource = new byte[(int)chainSliceBytes];
                        if (!TryReadTextureGuestMemory(ctx,
                                descriptor.Address + layer * chainSliceBytes + baseMipByteOffset,
                                sliceSource))
                        {
                            break;
                        }

                        var sliceLinear = TryDetileTextureSource(
                            descriptor,
                            sourceWidth,
                            layerBytes,
                            sliceSource,
                            baseMipInTail,
                            mipTailElementX,
                            mipTailElementY) ?? sliceSource.AsSpan(0, layerBytes).ToArray();
                        sliceLinear.AsSpan(0, layerBytes)
                            .CopyTo(layered.AsSpan(checked((int)(layer * layerBytes))));
                        uploadedLayers++;
                    }
                }

                if (uploadedLayers == arrayLayers)
'@
        $text=Replace-UniqueLiteralV74015 -Text $text -Old $cpuOld -New $cpuNew -Description "CPU linear array single-flight"

        if(-not $text.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT") -or
           -not $text.Contains("[V74.0.15][ARRAY_SINGLEFLIGHT] owner") -or
           -not $text.Contains("[V74.0.15][ARRAY_SINGLEFLIGHT] reuse") -or
           $text.Contains("var tiledLayers = new byte[(long)sliceBytes * arrayLayers];") -or
           $text.Contains("var layered = new byte[totalBytes];")){
            throw "[V74.0.15] Post-patch structural verification failed."
        }

        $bytes=[System.IO.File]::ReadAllBytes($agc)
        $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $writeText=$text
        if($sourceUsesCrLf){ $writeText=$writeText.Replace("`n","`r`n") }
        [System.IO.File]::WriteAllText($agc,$writeText,[System.Text.UTF8Encoding]::new($bom))
        $sourceChanged=$true
        Write-Host "[V74.0.15] Large-array exact snapshot single-flight installed (GPU tiled + CPU linear paths)."
        Write-Host "[V74.0.15] V74.0.5 non-array reuse bounded to 8..32 MB."
    }
    else{
        Write-Host "[V74.0.15] Large-array single-flight already installed; build only."
    }

    $post=[System.IO.File]::ReadAllText($agc)
    foreach($guard in @(
        "SHARPEMU_V74_0_4_DCC_NO_CPU_SNAPSHOT",
        "SHARPEMU_V74_0_5_LARGE_TEXTURE_SNAPSHOT_REUSE",
        "SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT",
        "V74015LargeArraySnapshotTtlMs = 500L",
        "[V74.0.15][ARRAY_SINGLEFLIGHT] owner",
        "[V74.0.15][ARRAY_SINGLEFLIGHT] reuse"
    )){
        if(-not $post.Contains($guard)){ throw "[V74.0.15] Cumulative/post-patch guard missing: $guard" }
    }

    Write-Host "[V74.0.15] Building Debug win-x64..."
    Invoke-DotNetCheckedV74015 -Root $root -Arguments @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Debug","-r","win-x64","--nologo")

    Write-Host "[V74.0.15] Building Release win-x64..."
    Invoke-DotNetCheckedV74015 -Root $root -Arguments @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Release","-r","win-x64","--nologo")

    Sync-ReleaseRuntimeAssetsV74015 -Root $root
}
catch{
    if($sourceChanged -and [System.IO.File]::Exists($backupAgc)){
        Copy-Item -LiteralPath $backupAgc -Destination $agc -Force
        Write-Host "[V74.0.15] Apply/build failed; AgcExports.cs restored."
    }
    throw
}

Write-Host "[V74.0.15] Backup: $backupRoot"
Write-Host "[V74.0.15] FINAL agc_sha=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.15] SUCCESS"
Write-Host "[V74.0.15] Next: RUN_4_DEMONS_ARRAY_SINGLEFLIGHT.cmd"
