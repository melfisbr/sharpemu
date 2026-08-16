Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRootV74023 {
    param([string]$RepositoryRoot = "")
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = (Get-Location).Path
    }
    $repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $marker = [System.IO.Path]::Combine($repoRoot, "src", "SharpEmu.CLI", "SharpEmu.CLI.csproj")
    if (-not [System.IO.File]::Exists($marker)) {
        throw "[V74.0.23] Repository root invalid: $repoRoot"
    }
    return $repoRoot
}

function Get-AgcPathV74023 {
    param([string]$Root)
    $path = [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Agc", "AgcExports.cs")
    if (-not [System.IO.File]::Exists($path)) {
        throw "[V74.0.23] Missing AgcExports.cs: $path"
    }
    return $path
}

function Get-CpuPathV74023 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Core", "Cpu", "CpuDispatcher.cs")
}

function Get-DirectPathV74023 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Core", "Cpu", "Native", "DirectExecutionBackend.cs")
}

function Get-KernelPathV74023 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Kernel", "KernelExports.cs")
}

function Get-HostMoviePathV74023 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Media", "HostMovieBridge.cs")
}

function Get-CSharpMethodSpanV74023 {
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "[V74.0.23] C# method signature missing: $Signature" }
    if ($Text.IndexOf($Signature, $start + $Signature.Length, [System.StringComparison]::Ordinal) -ge 0) {
        throw "[V74.0.23] C# method signature not unique: $Signature"
    }
    $openBrace = $Text.IndexOf('{', $start)
    if ($openBrace -lt 0) { throw "[V74.0.23] Opening brace missing: $Signature" }
    $depth = 0
    $end = -1
    for ($charIndex = $openBrace; $charIndex -lt $Text.Length; $charIndex++) {
        $character = $Text[$charIndex]
        if ($character -eq '{') { $depth++ }
        elseif ($character -eq '}') {
            $depth--
            if ($depth -eq 0) { $end = $charIndex + 1; break }
        }
    }
    if ($end -lt 0) { throw "[V74.0.23] Closing brace missing: $Signature" }
    return [pscustomobject]@{ Start = $start; End = $end; Text = $Text.Substring($start, $end - $start) }
}

function Test-V21AbiAppliedV74023 {
    param([string]$Root)
    $cpuPath = Get-CpuPathV74023 -Root $Root
    $directPath = Get-DirectPathV74023 -Root $Root
    $kernelPath = Get-KernelPathV74023 -Root $Root
    foreach ($requiredPath in @($cpuPath, $directPath, $kernelPath)) {
        if (-not [System.IO.File]::Exists($requiredPath)) { return $false }
    }
    $cpuText = [System.IO.File]::ReadAllText($cpuPath)
    $directText = [System.IO.File]::ReadAllText($directPath)
    $kernelText = [System.IO.File]::ReadAllText($kernelPath)
    return $cpuText.Contains("SHARPEMU_V74_0_21_EBOOT_ENTRY_ABI") -and
        $cpuText.Contains("const ulong entryParamsSize = 0x118;") -and
        $cpuText.Contains("const int maxArguments = 33;") -and
        $directText.Contains("SHARPEMU_V74_0_21_LLE_INIT_ENV_GATE") -and
        $kernelText.Contains("SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC")
}

function Get-V23StateV74023 {
    param([string]$Text)
    $marker = $Text.Contains("SHARPEMU_V74_0_23_LARGE_ARRAY_CACHE_TRUST")
    $gate = $Text.Contains('Environment.GetEnvironmentVariable("SHARPEMU_LARGE_ARRAY_CACHE_TRUST")')
    $hit = $Text.Contains("[V74.0.23][ARRAY_CACHE_TRUST] hit")
    if ($marker -and $gate -and $hit) { return "Applied" }
    if ($marker -or $gate -or $hit) { return "Partial" }
    if (-not $Text.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT")) { return "Unknown" }
    if (-not $Text.Contains("V74015LargeArrayThresholdBytes")) { return "Unknown" }
    if (-not $Text.Contains("TEXTURE_CACHE_STALE") -or -not $Text.Contains("missing-baseline")) { return "Unknown" }
    $method = Get-CSharpMethodSpanV74023 -Text $Text -Signature "private static bool TryCreateGuestDrawTexture("
    $generationAnchor = @'
        var hasWriteGeneration =
            SharpEmu.HLE.GuestImageWriteTracker.TryGetWriteGeneration(
                descriptor.Address,
                out var writeGeneration);
'@
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $generationAnchor = $generationAnchor.Replace("`r`n", "`n").Replace("`n", $newline).TrimStart($newline.ToCharArray())
    $generationCount = ([regex]::Matches($method.Text, [regex]::Escape($generationAnchor))).Count
    if ($generationCount -ne 1) { return "Unknown" }
    if (-not $method.Text.Contains("GuestGpu.Current.IsTextureContentCached(")) { return "Unknown" }
    if (-not $method.Text.Contains("if (wantsArrayUpload)")) { return "Unknown" }
    return "Baseline"
}

function Convert-AgcV74023 {
    param([string]$Text)
    $state = Get-V23StateV74023 -Text $Text
    if ($state -eq "Applied") { return $Text }
    if ($state -ne "Baseline") { throw "[V74.0.23] AGC transform state is $state; refusing source modification." }

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $fieldAnchor = "    private static int _v74015LargeArraySnapshotReuseTraceCount;"
    if (([regex]::Matches($Text, [regex]::Escape($fieldAnchor))).Count -ne 1) {
        throw "[V74.0.23] V74.0.15 field anchor is not unique."
    }
    $fieldInsert = @'
    private static int _v74015LargeArraySnapshotReuseTraceCount;

    // SHARPEMU_V74_0_23_LARGE_ARRAY_CACHE_TRUST
    // Opt-in repair for very large array textures whose later sparse cache
    // validator has no baseline. We may reuse only an exact presenter-resident
    // identity and only while the guest CPU write tracker reports it clean.
    private static readonly bool _v74023TrustLargeArrayCache = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_LARGE_ARRAY_CACHE_TRUST"),
        "1",
        StringComparison.Ordinal);
    private static long _v74023LargeArrayCacheTrustHitCount;
'@
    $fieldInsert = $fieldInsert.Replace("`r`n", "`n").Replace("`n", $newline).TrimStart($newline.ToCharArray()).TrimEnd()
    $Text = $Text.Replace($fieldAnchor, $fieldInsert)

    $method = Get-CSharpMethodSpanV74023 -Text $Text -Signature "private static bool TryCreateGuestDrawTexture("
    $generationAnchor = @'
        var hasWriteGeneration =
            SharpEmu.HLE.GuestImageWriteTracker.TryGetWriteGeneration(
                descriptor.Address,
                out var writeGeneration);
'@
    $generationAnchor = $generationAnchor.Replace("`r`n", "`n").Replace("`n", $newline).TrimStart($newline.ToCharArray())
    $relativeIndex = $method.Text.IndexOf($generationAnchor, [System.StringComparison]::Ordinal)
    if ($relativeIndex -lt 0 -or $method.Text.IndexOf($generationAnchor, $relativeIndex + $generationAnchor.Length, [System.StringComparison]::Ordinal) -ge 0) {
        throw "[V74.0.23] write-generation insertion anchor is missing or not unique."
    }
    $insertAt = $method.Start + $relativeIndex + $generationAnchor.Length
    $fastPath = @'

        // V74.0.23: V73.0.19.1 reports missing-baseline for the 320 MiB
        // 80-layer array even after the presenter has cached that exact identity.
        // In opt-in mode, short-circuit before that validator. No pixels/layers are
        // fabricated or dropped: the presenter must already own the exact resource.
        var v74023LargeArrayByteCount =
            wantsArrayUpload && arrayUploadLayers != 0 &&
            physicalSourceByteCount <= (ulong)long.MaxValue / arrayUploadLayers
                ? (long)(physicalSourceByteCount * arrayUploadLayers)
                : long.MaxValue;
        if (_v74023TrustLargeArrayCache &&
            !_textureCopySkipDisabled &&
            wantsArrayUpload &&
            v74023LargeArrayByteCount >= V74015LargeArrayThresholdBytes &&
            descriptor.Address != 0 &&
            !SharpEmu.HLE.GuestImageWriteTracker.PeekDirty(descriptor.Address) &&
            GuestGpu.Current.IsTextureContentCached(
                new TextureContentIdentity(
                    descriptor.Address,
                    descriptor.Width,
                    descriptor.Height,
                    descriptor.Format,
                    descriptor.NumberType,
                    descriptor.DstSelect,
                    descriptor.TileMode,
                    sourceWidth,
                    sampler,
                    isArrayed,
                    arrayUploadLayers,
                    descriptor.Type,
                    textureDepth,
                    MetadataAddress: descriptor.MetadataAddress,
                    DescriptorFlags: descriptor.DescriptorFlags,
                    BcSwizzle: descriptor.BcSwizzle,
                    HasExtendedDescriptor: descriptor.HasExtendedDescriptor)))
        {
            var v74023Hit = Interlocked.Increment(ref _v74023LargeArrayCacheTrustHitCount);
            if (v74023Hit <= 32 || v74023Hit % 256 == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.23][ARRAY_CACHE_TRUST] hit count={v74023Hit} " +
                    $"addr=0x{descriptor.Address:X16} size={descriptor.Width}x{descriptor.Height} " +
                    $"layers={arrayUploadLayers} bytes={v74023LargeArrayByteCount} " +
                    $"write_gen={(hasWriteGeneration ? writeGeneration : -1)}");
            }

            NoteSampledAddress(descriptor.Address, descriptor.Format, descriptor.NumberType);
            texture = new GuestDrawTexture(
                descriptor.Address,
                descriptor.Width,
                descriptor.Height,
                descriptor.Format,
                descriptor.NumberType,
                [],
                IsFallback: false,
                IsStorage: false,
                MipLevels: descriptor.MipLevels,
                MipLevel: mipLevel,
                BaseMipLevel: descriptor.ViewBaseLevel,
                ResourceMipLevels: descriptor.ResourceMipLevels,
                Pitch: sourceWidth,
                TileMode: descriptor.TileMode,
                DstSelect: descriptor.DstSelect,
                Sampler: sampler,
                WriteGeneration: hasWriteGeneration ? writeGeneration : -1,
                ArrayedView: isArrayed,
                ArrayLayers: arrayUploadLayers,
                Type: descriptor.Type,
                Depth: textureDepth,
                MetadataAddress: descriptor.MetadataAddress,
                DescriptorFlags: descriptor.DescriptorFlags,
                BcSwizzle: descriptor.BcSwizzle,
                HasExtendedDescriptor: descriptor.HasExtendedDescriptor);
            return true;
        }
'@
    $fastPath = $fastPath.Replace("`r`n", "`n").Replace("`n", $newline).TrimEnd()
    $Text = $Text.Insert($insertAt, $fastPath)
    if ((Get-V23StateV74023 -Text $Text) -ne "Applied") {
        throw "[V74.0.23] In-memory post-transform verification failed."
    }
    return $Text
}

function Invoke-DotNetCheckedV74023 {
    param([string]$Root, [string[]]$Arguments)
    Push-Location $Root
    try {
        & dotnet @Arguments
        if ($LASTEXITCODE -ne 0) { throw "[V74.0.23] dotnet failed with exit code $LASTEXITCODE" }
    }
    finally { Pop-Location }
}

function Sync-ReleaseRuntimeAssetsV74023 {
    param([string]$Root)
    $debugRoot = [System.IO.Path]::Combine($Root, "artifacts", "bin", "Debug", "net10.0", "win-x64")
    $releaseRoot = [System.IO.Path]::Combine($Root, "artifacts", "bin", "Release", "net10.0", "win-x64")
    if (-not [System.IO.Directory]::Exists($releaseRoot)) { return }
    foreach ($assetName in @("plugins", "pipeline_cache")) {
        $source = [System.IO.Path]::Combine($debugRoot, $assetName)
        $destination = [System.IO.Path]::Combine($releaseRoot, $assetName)
        if ([System.IO.Directory]::Exists($source)) {
            if (-not [System.IO.Directory]::Exists($destination)) { [System.IO.Directory]::CreateDirectory($destination) | Out-Null }
            Copy-Item -Path ([System.IO.Path]::Combine($source, "*")) -Destination $destination -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TextSharedV74023 {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return "" }
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try {
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true, 65536, $false)
                try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        catch { Start-Sleep -Milliseconds 100 }
    }
    return ""
}

function Get-DescendantProcessIdsV74023 {
    param([int]$ParentId)
    $result = New-Object 'System.Collections.Generic.List[int]'
    $queue = New-Object 'System.Collections.Generic.Queue[int]'
    $queue.Enqueue($ParentId)
    while ($queue.Count -gt 0) {
        $currentId = $queue.Dequeue()
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentId" -ErrorAction SilentlyContinue)
        foreach ($childProcess in $children) {
            $childId = [int]$childProcess.ProcessId
            if (-not $result.Contains($childId)) { $result.Add($childId); $queue.Enqueue($childId) }
        }
    }
    return @($result)
}
