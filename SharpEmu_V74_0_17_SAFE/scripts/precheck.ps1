param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74017 -RepositoryRoot $RepositoryRoot
$pthread=Get-PthreadPathV74017 -Root $root
$agc=Get-AgcPathV74017 -Root $root
$presenter=Get-PresenterPathV74017 -Root $root
$nativeWorker=Get-NativeWorkerPathV74017 -Root $root
$hostMovie=Get-HostMovieBridgePathV74017 -Root $root

$pthreadText=[System.IO.File]::ReadAllText($pthread)
$state=Get-PthreadOpaqueOwnerGateStateV74017 -Text $pthreadText
if($state.State -notin @("Ready","Applied")){
    throw "[V74.0.17] Pthread structural state rejected: $($state.State) / $($state.Detail)"
}

# PRECHECK deliberately executes the exact transformer used by APPLY against an
# in-memory copy. If it cannot produce a complete Applied state, RUN_3 will not
# be allowed to start.
$probeText=Add-PthreadOpaqueOwnerGateV74017 -Text $pthreadText
$probeState=Get-PthreadOpaqueOwnerGateStateV74017 -Text $probeText
if($probeState.State -ne "Applied"){
    throw "[V74.0.17] Transformer probe failed: $($probeState.State) / $($probeState.Detail)"
}

$agcText=[System.IO.File]::ReadAllText($agc)
foreach($guard in @(
    "SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT",
    "SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY",
    "SHARPEMU_DCC_ALIAS_HISTORY_MS",
    "SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS"
)){
    if(-not $agcText.Contains($guard)){
        throw "[V74.0.17] Required cumulative AGC guard missing: $guard"
    }
}

$presenterText=[System.IO.File]::ReadAllText($presenter)
foreach($presenterGuard in @(
    "SHARPEMU_V74_0_12_BINK_COMPLETION_VISUAL_RELEASE",
    "SHARPEMU_RENDER_SCALE",
    "SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB",
    "SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET"
)){
    if(-not $presenterText.Contains($presenterGuard)){
        throw "[V74.0.17] Presenter cumulative guard missing: $presenterGuard"
    }
}

$nativeText=[System.IO.File]::ReadAllText($nativeWorker)
foreach($nativeGuard in @(
    "SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE",
    "SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT"
)){
    if(-not $nativeText.Contains($nativeGuard)){
        throw "[V74.0.17] Native worker cumulative guard missing: $nativeGuard"
    }
}

$hostMovieText=[System.IO.File]::ReadAllText($hostMovie)
foreach($hostMovieGuard in @(
    "SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF",
    "startup_completion_shim_header_fallback"
)){
    if(-not $hostMovieText.Contains($hostMovieGuard)){
        throw "[V74.0.17] Startup Bink handoff cumulative guard missing: $hostMovieGuard"
    }
}

Write-Host "[V74.0.17] PRECHECK PASSED (pthread transformer probe uses APPLY path)."
Write-Host "[V74.0.17] Pthread sha=$((Get-FileHash -LiteralPath $pthread -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.17] AGC sha=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.17] pthread_gate_state=$($state.State)"
Write-Host "[V74.0.17] V74.0.16.1 evidence: DCC history seeded 64 times and produced 0 history hits; runner will disable it."
Write-Host "[V74.0.17] V74.0.16.1 evidence: main loop=31.8781s; GatherResourceFileInfo=42.1034s; no natural Bink."
Write-Host "[V74.0.17] Target: remove DBFZ-only adaptive-mutex opaque-owner guest-memory sync from this Demon's Souls A/B run without changing mutex semantics."
