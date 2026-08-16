param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74018 -RepositoryRoot $RepositoryRoot
$direct=Get-DirectExecutionBackendPathV74018 -Root $root
$pthread=Get-PthreadPathV74018 -Root $root
$agc=Get-AgcPathV74018 -Root $root
$presenter=Get-PresenterPathV74018 -Root $root
$nativeWorker=Get-NativeWorkerPathV74018 -Root $root
$hostMovie=Get-HostMovieBridgePathV74018 -Root $root

$directText=[System.IO.File]::ReadAllText($direct)
$state=Get-NativeMemcpyIntrinsicGateStateV74018 -Text $directText
if($state.State -notin @("Ready","Applied")){
    throw "[V74.0.18] DirectExecutionBackend structural state rejected: $($state.State) / $($state.Detail)"
}
$probeText=Add-NativeMemcpyIntrinsicGateV74018 -Text $directText
$probeState=Get-NativeMemcpyIntrinsicGateStateV74018 -Text $probeText
if($probeState.State -ne "Applied"){
    throw "[V74.0.18] Native memcpy transformer probe failed: $($probeState.State) / $($probeState.Detail)"
}

# Q3VBxCXhUHs must still be HLE-preferred by default. RUN_4 alone opts into
# the native intrinsic, so other games retain the accumulated policy.
foreach($needle in @(
    '"Q3VBxCXhUHs" =>',
    'string.Equals(nid, "Q3VBxCXhUHs", StringComparison.Ordinal)'
)){
    if(-not $directText.Contains($needle)){
        throw "[V74.0.18] Native memcpy baseline missing: $needle"
    }
}

$pthreadText=[System.IO.File]::ReadAllText($pthread)
$pthreadState="Applied"
foreach($pthreadGuard in @(
    "SHARPEMU_V74_0_17_DEMONS_PTHREAD_OPAQUE_OWNER_GATE",
    "SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC",
    "_v74017OpaqueOwnerSyncEnabled"
)){
    if(-not $pthreadText.Contains($pthreadGuard)){
        $pthreadState="Missing"
        throw "[V74.0.18] V74.0.17 pthread cumulative guard missing: $pthreadGuard. Run V74.0.17 RUN_3 first."
    }
}

$agcText=[System.IO.File]::ReadAllText($agc)
foreach($guard in @(
    "SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT",
    "SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY",
    "SHARPEMU_DCC_ALIAS_HISTORY_MS",
    "SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS"
)){
    if(-not $agcText.Contains($guard)){throw "[V74.0.18] Required cumulative AGC guard missing: $guard"}
}

$presenterText=[System.IO.File]::ReadAllText($presenter)
foreach($guard in @(
    "SHARPEMU_V74_0_12_BINK_COMPLETION_VISUAL_RELEASE",
    "SHARPEMU_RENDER_SCALE",
    "ScaleGuestDimension",
    "SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB"
)){
    if(-not $presenterText.Contains($guard)){throw "[V74.0.18] Presenter cumulative guard missing: $guard"}
}

$nativeText=[System.IO.File]::ReadAllText($nativeWorker)
foreach($guard in @("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE","SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT")){
    if(-not $nativeText.Contains($guard)){throw "[V74.0.18] Native worker cumulative guard missing: $guard"}
}

$hostMovieText=[System.IO.File]::ReadAllText($hostMovie)
foreach($guard in @("SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF","startup_completion_shim_header_fallback")){
    if(-not $hostMovieText.Contains($guard)){throw "[V74.0.18] Startup Bink handoff cumulative guard missing: $guard"}
}

Write-Host "[V74.0.18] PRECHECK PASSED (native memcpy transformer probe uses APPLY path)."
Write-Host "[V74.0.18] DirectExecutionBackend sha=$((Get-FileHash -LiteralPath $direct -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.18] native_memcpy_gate_state=$($state.State) pthread_gate_state=$pthreadState"
Write-Host "[V74.0.18] V74.0.17 evidence: 33,554,432 managed import calls were reached; every 8M checkpoint named Q3VBxCXhUHs (libc memcpy)."
Write-Host "[V74.0.18] V74.0.17 evidence: presented guest image was 960x540 because RUN_4 forced render_scale=0.25."
Write-Host "[V74.0.18] Target: native memcpy A/B + restore native render scale 1.0; pthread compatibility returns to enabled."
