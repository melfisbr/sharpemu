Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRootV740231 {
    param([string]$RepositoryRoot = "")
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = (Get-Location).Path
    }
    $repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $markerPath = [System.IO.Path]::Combine($repoRoot, "src", "SharpEmu.CLI", "SharpEmu.CLI.csproj")
    if (-not [System.IO.File]::Exists($markerPath)) {
        throw "[V74.0.23.1] Repository root invalid: $repoRoot"
    }
    return $repoRoot
}

function Get-PresenterPathV740231 {
    param([string]$Root)
    $sourcePath = [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "VideoOut", "VulkanVideoPresenter.cs")
    if (-not [System.IO.File]::Exists($sourcePath)) {
        throw "[V74.0.23.1] Missing VulkanVideoPresenter.cs: $sourcePath"
    }
    return $sourcePath
}

function Get-AgcPathV740231 {
    param([string]$Root)
    $sourcePath = [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Agc", "AgcExports.cs")
    if (-not [System.IO.File]::Exists($sourcePath)) {
        throw "[V74.0.23.1] Missing AgcExports.cs: $sourcePath"
    }
    return $sourcePath
}

function Get-CpuPathV740231 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Core", "Cpu", "CpuDispatcher.cs")
}

function Get-DirectPathV740231 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Core", "Cpu", "Native", "DirectExecutionBackend.cs")
}

function Get-KernelPathV740231 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Kernel", "KernelExports.cs")
}

function Get-HostMoviePathV740231 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Media", "HostMovieBridge.cs")
}

function Test-V21AbiAppliedV740231 {
    param([string]$Root)
    $cpuPath = Get-CpuPathV740231 -Root $Root
    $directPath = Get-DirectPathV740231 -Root $Root
    $kernelPath = Get-KernelPathV740231 -Root $Root
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

function Get-V231StateV740231 {
    param([string]$Text)
    $normalized = $Text.Replace("`r`n", "`n")
    $marker = $normalized.Contains("SHARPEMU_V74_0_23_1_LARGE_ARRAY_SPARSE_BASELINE")
    $trace = $normalized.Contains("[V74.0.23.1][ARRAY_BASELINE]")
    $limit = $normalized.Contains("V740231MaxLargeArraySparseProbeBytes")
    if ($marker -and $trace -and $limit) { return "Applied" }
    if ($marker -or $trace -or $limit) { return "Partial" }

    if (-not $normalized.Contains("SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19")) { return "Unknown" }
    if (-not $normalized.Contains("SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_REFRESH_STRUCTURAL_V73_0_19_1")) { return "Unknown" }
    if (-not $normalized.Contains('private static bool TryBuildUntrackedTextureProbe(')) { return "Unknown" }
    if (-not $normalized.Contains('private static ulong ComputeSparseGuestContentProbe(')) { return "Unknown" }

    $fieldAnchor = @'
    private static long _v73019TextureCacheStaleTraceCount;
    private static long _v73019TextureCacheRefreshTraceCount;
'@
    $guardAnchor = @'
        probe = default;
        if (texture.Address == 0 ||
            byteCount == 0 ||
            byteCount > MaxTrackedGuestImageBytes)
        {
            return false;
        }
'@
    $probeTailAnchor = @'
        probe = new UntrackedTextureCacheProbe(
            ComputeSparseGuestContentProbe(
                memory,
                texture.Address,
                byteCount),
            byteCount);
        return true;
'@
    $fieldAnchor = $fieldAnchor.Replace("`r`n", "`n").TrimStart("`n".ToCharArray())
    $guardAnchor = $guardAnchor.Replace("`r`n", "`n").TrimStart("`n".ToCharArray())
    $probeTailAnchor = $probeTailAnchor.Replace("`r`n", "`n").TrimStart("`n".ToCharArray())
    if (([regex]::Matches($normalized, [regex]::Escape($fieldAnchor))).Count -ne 1) { return "Unknown" }
    if (([regex]::Matches($normalized, [regex]::Escape($guardAnchor))).Count -ne 1) { return "Unknown" }
    if (([regex]::Matches($normalized, [regex]::Escape($probeTailAnchor))).Count -ne 1) { return "Unknown" }
    return "Baseline"
}

function Convert-PresenterV740231 {
    param([string]$Text)
    $state = Get-V231StateV740231 -Text $Text
    if ($state -eq "Applied") { return $Text }
    if ($state -ne "Baseline") {
        throw "[V74.0.23.1] Presenter transform state is $state; refusing source modification."
    }

    $hadCrlf = $Text.Contains("`r`n")
    $normalized = $Text.Replace("`r`n", "`n")

    $fieldAnchor = @'
    private static long _v73019TextureCacheStaleTraceCount;
    private static long _v73019TextureCacheRefreshTraceCount;
'@
    $fieldReplacement = @'
    private static long _v73019TextureCacheStaleTraceCount;
    private static long _v73019TextureCacheRefreshTraceCount;

    // SHARPEMU_V74_0_23_1_LARGE_ARRAY_SPARSE_BASELINE
    // V73.0.19.1 used MaxTrackedGuestImageBytes (128 MiB) as a hard gate even
    // though ComputeSparseGuestContentProbe reads only 8 x 64-byte samples.
    // Permit a bounded large ARRAY cache identity to build the same sparse
    // baseline without allocating/copying the complete texture again.
    private const ulong V740231MaxLargeArraySparseProbeBytes =
        512UL * 1024UL * 1024UL;
    private static long _v740231LargeArrayBaselineTraceCount;
'@
    $guardAnchor = @'
        probe = default;
        if (texture.Address == 0 ||
            byteCount == 0 ||
            byteCount > MaxTrackedGuestImageBytes)
        {
            return false;
        }
'@
    $guardReplacement = @'
        probe = default;
        var v740231LargeArraySparseProbe =
            texture.ArrayedView &&
            texture.ArrayLayers > 1 &&
            byteCount > MaxTrackedGuestImageBytes &&
            byteCount <= V740231MaxLargeArraySparseProbeBytes;
        if (texture.Address == 0 ||
            byteCount == 0 ||
            (byteCount > MaxTrackedGuestImageBytes &&
             !v740231LargeArraySparseProbe))
        {
            return false;
        }
'@
    $probeTailAnchor = @'
        probe = new UntrackedTextureCacheProbe(
            ComputeSparseGuestContentProbe(
                memory,
                texture.Address,
                byteCount),
            byteCount);
        return true;
'@
    $probeTailReplacement = @'
        probe = new UntrackedTextureCacheProbe(
            ComputeSparseGuestContentProbe(
                memory,
                texture.Address,
                byteCount),
            byteCount);
        if (v740231LargeArraySparseProbe)
        {
            var baselineCount = Interlocked.Increment(
                ref _v740231LargeArrayBaselineTraceCount);
            if (baselineCount <= 32 ||
                (baselineCount & (baselineCount - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.23.1][ARRAY_BASELINE] count={baselineCount} " +
                    $"addr=0x{texture.Address:X16} size={texture.Width}x{texture.Height} " +
                    $"layers={texture.ArrayLayers} bytes={byteCount} sparse_read_bytes=512");
            }
        }
        return true;
'@

    $fieldAnchor = $fieldAnchor.Replace("`r`n", "`n").TrimStart("`n".ToCharArray())
    $fieldReplacement = $fieldReplacement.Replace("`r`n", "`n").TrimStart("`n".ToCharArray()).TrimEnd()
    $guardAnchor = $guardAnchor.Replace("`r`n", "`n").TrimStart("`n".ToCharArray())
    $guardReplacement = $guardReplacement.Replace("`r`n", "`n").TrimStart("`n".ToCharArray()).TrimEnd()
    $probeTailAnchor = $probeTailAnchor.Replace("`r`n", "`n").TrimStart("`n".ToCharArray())
    $probeTailReplacement = $probeTailReplacement.Replace("`r`n", "`n").TrimStart("`n".ToCharArray()).TrimEnd()

    if (([regex]::Matches($normalized, [regex]::Escape($fieldAnchor))).Count -ne 1) {
        throw "[V74.0.23.1] Presenter field anchor is missing or not unique."
    }
    if (([regex]::Matches($normalized, [regex]::Escape($guardAnchor))).Count -ne 1) {
        throw "[V74.0.23.1] Presenter probe guard anchor is missing or not unique."
    }
    if (([regex]::Matches($normalized, [regex]::Escape($probeTailAnchor))).Count -ne 1) {
        throw "[V74.0.23.1] Presenter sparse-probe tail anchor is missing or not unique."
    }

    $normalized = $normalized.Replace($fieldAnchor, $fieldReplacement)
    $normalized = $normalized.Replace($guardAnchor, $guardReplacement)
    $normalized = $normalized.Replace($probeTailAnchor, $probeTailReplacement)
    if ((Get-V231StateV740231 -Text $normalized) -ne "Applied") {
        throw "[V74.0.23.1] In-memory post-transform verification failed."
    }

    if ($hadCrlf) { return $normalized.Replace("`n", "`r`n") }
    return $normalized
}

function Invoke-DotNetCheckedV740231 {
    param([string]$Root, [string[]]$Arguments)
    Push-Location $Root
    try {
        & dotnet @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "[V74.0.23.1] dotnet failed with exit code $LASTEXITCODE"
        }
    }
    finally { Pop-Location }
}

function Sync-ReleaseRuntimeAssetsV740231 {
    param([string]$Root)
    $debugRoot = [System.IO.Path]::Combine($Root, "artifacts", "bin", "Debug", "net10.0", "win-x64")
    $releaseRoot = [System.IO.Path]::Combine($Root, "artifacts", "bin", "Release", "net10.0", "win-x64")
    if (-not [System.IO.Directory]::Exists($releaseRoot)) { return }
    foreach ($assetName in @("plugins", "pipeline_cache")) {
        $sourcePath = [System.IO.Path]::Combine($debugRoot, $assetName)
        $destinationPath = [System.IO.Path]::Combine($releaseRoot, $assetName)
        if ([System.IO.Directory]::Exists($sourcePath)) {
            if (-not [System.IO.Directory]::Exists($destinationPath)) {
                [System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null
            }
            Copy-Item -Path ([System.IO.Path]::Combine($sourcePath, "*")) -Destination $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TextSharedV740231 {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return "" }
    for ($attemptIndex = 0; $attemptIndex -lt 5; $attemptIndex++) {
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

function Get-DescendantProcessIdsV740231 {
    param([int]$ParentId)
    $result = New-Object 'System.Collections.Generic.List[int]'
    $queue = New-Object 'System.Collections.Generic.Queue[int]'
    $queue.Enqueue($ParentId)
    while ($queue.Count -gt 0) {
        $currentId = $queue.Dequeue()
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentId" -ErrorAction SilentlyContinue)
        foreach ($childProcess in $children) {
            $childId = [int]$childProcess.ProcessId
            if (-not $result.Contains($childId)) {
                $result.Add($childId)
                $queue.Enqueue($childId)
            }
        }
    }
    return @($result)
}
