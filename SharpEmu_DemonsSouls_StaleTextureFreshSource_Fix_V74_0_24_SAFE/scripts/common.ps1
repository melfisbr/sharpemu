Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRootV74024 {
    param([string]$RepositoryRoot = "")
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Get-Location).Path }
    $repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $markerPath = [System.IO.Path]::Combine($repoRoot, "src", "SharpEmu.CLI", "SharpEmu.CLI.csproj")
    if (-not [System.IO.File]::Exists($markerPath)) { throw "[V74.0.24] Repository root invalid: $repoRoot" }
    return $repoRoot
}

function Get-PresenterPathV74024 {
    param([string]$Root)
    $sourcePath = [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "VideoOut", "VulkanVideoPresenter.cs")
    if (-not [System.IO.File]::Exists($sourcePath)) { throw "[V74.0.24] Missing VulkanVideoPresenter.cs: $sourcePath" }
    return $sourcePath
}

function Get-AgcPathV74024 {
    param([string]$Root)
    return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Agc", "AgcExports.cs")
}
function Get-CpuPathV74024 { param([string]$Root) return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Core", "Cpu", "CpuDispatcher.cs") }
function Get-DirectPathV74024 { param([string]$Root) return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Core", "Cpu", "Native", "DirectExecutionBackend.cs") }
function Get-KernelPathV74024 { param([string]$Root) return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Kernel", "KernelExports.cs") }
function Get-HostMoviePathV74024 { param([string]$Root) return [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Media", "HostMovieBridge.cs") }

function Test-V21AbiAppliedV74024 {
    param([string]$Root)
    $cpuPath = Get-CpuPathV74024 -Root $Root
    $directPath = Get-DirectPathV74024 -Root $Root
    $kernelPath = Get-KernelPathV74024 -Root $Root
    foreach ($requiredPath in @($cpuPath,$directPath,$kernelPath)) { if (-not [System.IO.File]::Exists($requiredPath)) { return $false } }
    $cpuText=[System.IO.File]::ReadAllText($cpuPath)
    $directText=[System.IO.File]::ReadAllText($directPath)
    $kernelText=[System.IO.File]::ReadAllText($kernelPath)
    return $cpuText.Contains("SHARPEMU_V74_0_21_EBOOT_ENTRY_ABI") -and
        $cpuText.Contains("const ulong entryParamsSize = 0x118;") -and
        $cpuText.Contains("const int maxArguments = 33;") -and
        $directText.Contains("SHARPEMU_V74_0_21_LLE_INIT_ENV_GATE") -and
        $kernelText.Contains("SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC")
}

function Get-V24StateV74024 {
    param([string]$Text)
    $normalized=$Text.Replace("`r`n","`n")
    $marker=$normalized.Contains("SHARPEMU_V74_0_24_FRESH_STALE_SOURCE")
    $helper=$normalized.Contains("TryRefreshStaleTextureSourceV74024")
    $trace=$normalized.Contains("[V74.0.24][STALE_SOURCE_REFRESH]")
    if ($marker -and $helper -and $trace) { return "Applied" }
    if ($marker -or $helper -or $trace) { return "Partial" }
    if (-not $normalized.Contains("SHARPEMU_V74_0_23_1_LARGE_ARRAY_SPARSE_BASELINE")) { return "Unknown" }
    if (-not $normalized.Contains("SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_REFRESH_STRUCTURAL_V73_0_19_1")) { return "Unknown" }
    if (-not $normalized.Contains("private static bool TryReadGuestTextureBacking(")) { return "Unknown" }
    if (-not $normalized.Contains("private TextureResource GetOrCreateCachedTextureResource(GuestDrawTexture texture)")) { return "Unknown" }

    $fieldAnchor=@'
    private static long _v740231LargeArrayBaselineTraceCount;
'@
    $staleAnchor=@'
            // SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_REFRESH_STRUCTURAL_V73_0_19_1
            // A stale identity is evicted BEFORE the checkout-specific cache-hit
            // condition executes. This works whether that condition has extra
            // guards, logging, or generation checks in accumulated branches.
            if (_staleTextureIdentities.TryRemove(key, out _))
            {
'@
    $afterAnchor=@'
                    }
                }
            }
            if (_textureCache.TryGetValue(key, out var cached))
'@
    $methodAnchor=@'
        /// <summary>
        /// Guest textures are static assets in the common case, but every draw
'@
    foreach ($anchor in @($fieldAnchor,$staleAnchor,$afterAnchor,$methodAnchor)) {
        $a=$anchor.Replace("`r`n","`n").TrimStart("`n".ToCharArray())
        if (([regex]::Matches($normalized,[regex]::Escape($a))).Count -ne 1) { return "Unknown" }
    }
    return "Baseline"
}

function Convert-PresenterV74024 {
    param([string]$Text)
    $state=Get-V24StateV74024 -Text $Text
    if ($state -eq "Applied") { return $Text }
    if ($state -ne "Baseline") { throw "[V74.0.24] Presenter transform state is $state; refusing source modification." }
    $hadCrlf=$Text.Contains("`r`n")
    $normalized=$Text.Replace("`r`n","`n")

    $fieldAnchor=@'
    private static long _v740231LargeArrayBaselineTraceCount;
'@
    $fieldReplacement=@'
    private static long _v740231LargeArrayBaselineTraceCount;

    // SHARPEMU_V74_0_24_FRESH_STALE_SOURCE
    // The V73.0.19.1 coherence probe can detect that guest bytes changed after
    // a draw was translated. The cached resource is evicted correctly, but the
    // draw can still carry the OLD RgbaPixels/TiledSource snapshot. Re-uploading
    // that snapshot recreates the old baseline and causes an endless identical
    // old->new stale loop. Refresh a bounded source from current guest memory
    // before rebuilding that stale texture.
    private const ulong V74024MaxFreshStaleSourceBytes =
        64UL * 1024UL * 1024UL;
    private static long _v74024FreshStaleSourceTraceCount;
'@

    $staleAnchor=@'
            // SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_REFRESH_STRUCTURAL_V73_0_19_1
            // A stale identity is evicted BEFORE the checkout-specific cache-hit
            // condition executes. This works whether that condition has extra
            // guards, logging, or generation checks in accumulated branches.
            if (_staleTextureIdentities.TryRemove(key, out _))
            {
'@
    $staleReplacement=@'
            // SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_REFRESH_STRUCTURAL_V73_0_19_1
            // A stale identity is evicted BEFORE the checkout-specific cache-hit
            // condition executes. This works whether that condition has extra
            // guards, logging, or generation checks in accumulated branches.
            var v74024RefreshFromGuest = false;
            if (_staleTextureIdentities.TryRemove(key, out _))
            {
                v74024RefreshFromGuest = true;
'@

    $afterAnchor=@'
                    }
                }
            }
            if (_textureCache.TryGetValue(key, out var cached))
'@
    $afterReplacement=@'
                    }
                }
            }
            if (v74024RefreshFromGuest &&
                TryRefreshStaleTextureSourceV74024(
                    texture,
                    out var v74024FreshTexture))
            {
                texture = v74024FreshTexture;
            }
            if (_textureCache.TryGetValue(key, out var cached))
'@

    $methodAnchor=@'
        /// <summary>
        /// Guest textures are static assets in the common case, but every draw
'@
    $methodReplacement=@'
        private static bool TryRefreshStaleTextureSourceV74024(
            GuestDrawTexture texture,
            out GuestDrawTexture refreshed)
        {
            refreshed = texture;
            var memory = _guestMemory;
            if (memory is null || texture.Address == 0)
            {
                return false;
            }

            ulong sourceByteCount;
            if (texture.TileMode != 0)
            {
                // For tiled resources the already-translated draw knows the
                // exact physical backing span (including tile padding). Reuse
                // only that SIZE, never its stale contents.
                if (texture.TiledSource is not { Length: > 0 } tiledSource)
                {
                    return false;
                }
                sourceByteCount = (ulong)tiledSource.LongLength;
            }
            else
            {
                try
                {
                    var width = Math.Max(texture.Width, 1);
                    var height = Math.Max(texture.Height, 1);
                    var rowLength = Math.Max(texture.Pitch, width);
                    var depth = GetGuestTextureDepth(texture.Type, texture.Depth);
                    var layers = GetEffectiveTextureArrayLayers(
                        texture.Type,
                        texture.ArrayedView,
                        texture.ArrayLayers);
                    var perLayerOrVolume = GetTextureByteCount(
                        texture.Format,
                        rowLength,
                        height,
                        depth);
                    sourceByteCount = checked(perLayerOrVolume * layers);
                }
                catch (OverflowException)
                {
                    return false;
                }
            }

            if (sourceByteCount == 0 ||
                sourceByteCount > V74024MaxFreshStaleSourceBytes ||
                sourceByteCount > int.MaxValue)
            {
                return false;
            }

            var freshBytes = GC.AllocateUninitializedArray<byte>(
                checked((int)sourceByteCount));
            if (!TryReadGuestTextureBacking(
                    memory,
                    texture.Address,
                    freshBytes))
            {
                return false;
            }

            refreshed = texture.TileMode == 0
                ? texture with
                {
                    RgbaPixels = freshBytes,
                    TiledSource = null,
                }
                : texture with
                {
                    RgbaPixels = Array.Empty<byte>(),
                    TiledSource = freshBytes,
                };

            var refreshCount = Interlocked.Increment(
                ref _v74024FreshStaleSourceTraceCount);
            if (refreshCount <= 64 ||
                (refreshCount & (refreshCount - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.24][STALE_SOURCE_REFRESH] count={refreshCount} " +
                    $"addr=0x{texture.Address:X16} size={texture.Width}x{texture.Height} " +
                    $"bytes={sourceByteCount} tile={texture.TileMode} " +
                    $"array={(texture.ArrayedView ? 1 : 0)} source=" +
                    (texture.TileMode == 0 ? "linear" : "tiled"));
            }
            return true;
        }

        /// <summary>
        /// Guest textures are static assets in the common case, but every draw
'@

    $pairs=@(
        @($fieldAnchor,$fieldReplacement),
        @($staleAnchor,$staleReplacement),
        @($afterAnchor,$afterReplacement),
        @($methodAnchor,$methodReplacement)
    )
    foreach ($pair in $pairs) {
        $anchor=$pair[0].Replace("`r`n","`n").TrimStart("`n".ToCharArray())
        $replacement=$pair[1].Replace("`r`n","`n").TrimStart("`n".ToCharArray()).TrimEnd()
        if (([regex]::Matches($normalized,[regex]::Escape($anchor))).Count -ne 1) {
            throw "[V74.0.24] Presenter anchor missing or not unique."
        }
        $normalized=$normalized.Replace($anchor,$replacement)
    }
    if ((Get-V24StateV74024 -Text $normalized) -ne "Applied") { throw "[V74.0.24] In-memory post-transform verification failed." }
    if ($hadCrlf) { return $normalized.Replace("`n","`r`n") }
    return $normalized
}

function Invoke-DotNetCheckedV74024 {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try {
        & dotnet @Arguments
        if ($LASTEXITCODE -ne 0) { throw "[V74.0.24] dotnet failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
}

function Sync-ReleaseRuntimeAssetsV74024 {
    param([string]$Root)
    $debugRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Debug","net10.0","win-x64")
    $releaseRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Release","net10.0","win-x64")
    if (-not [System.IO.Directory]::Exists($releaseRoot)) { return }
    foreach ($assetName in @("plugins","pipeline_cache")) {
        $sourcePath=[System.IO.Path]::Combine($debugRoot,$assetName)
        $destinationPath=[System.IO.Path]::Combine($releaseRoot,$assetName)
        if ([System.IO.Directory]::Exists($sourcePath)) {
            if (-not [System.IO.Directory]::Exists($destinationPath)) { [System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null }
            Copy-Item -Path ([System.IO.Path]::Combine($sourcePath,"*")) -Destination $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TextSharedV74024 {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return "" }
    for ($attemptIndex=0;$attemptIndex -lt 5;$attemptIndex++) {
        try {
            $stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try {
                $reader=[System.IO.StreamReader]::new($stream,[System.Text.Encoding]::UTF8,$true,65536,$false)
                try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
        } catch { Start-Sleep -Milliseconds 100 }
    }
    return ""
}

function Get-DescendantProcessIdsV74024 {
    param([int]$ParentId)
    $result=New-Object 'System.Collections.Generic.List[int]'
    $queue=New-Object 'System.Collections.Generic.Queue[int]'
    $queue.Enqueue($ParentId)
    while ($queue.Count -gt 0) {
        $currentId=$queue.Dequeue()
        $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentId" -ErrorAction SilentlyContinue)
        foreach ($childProcess in $children) {
            $childId=[int]$childProcess.ProcessId
            if (-not $result.Contains($childId)) { $result.Add($childId); $queue.Enqueue($childId) }
        }
    }
    return @($result)
}
