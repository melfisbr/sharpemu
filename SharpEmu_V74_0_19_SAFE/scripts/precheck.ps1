param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74018 -RepositoryRoot $RepositoryRoot
$direct=Get-DirectExecutionBackendPathV74018 -Root $root
$hostMovie=Get-HostMovieBridgePathV74018 -Root $root
$agc=Get-AgcPathV74018 -Root $root
$presenter=Get-PresenterPathV74018 -Root $root
$nativeWorker=Get-NativeWorkerPathV74018 -Root $root

$directText=[System.IO.File]::ReadAllText($direct)
$memcpyState=Get-NativeMemcpyIntrinsicGateStateV74018 -Text $directText
if($memcpyState.State -ne "Applied"){
    throw "[V74.0.19] V74.0.18 native memcpy gate is not applied: $($memcpyState.State) / $($memcpyState.Detail). Run V74.0.18 RUN_3 first."
}

$hostMovieText=[System.IO.File]::ReadAllText($hostMovie)
$requiredBootGuards=@(
    "SHARPEMU_BINK_AUTO_BOOT",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "bink2.auto_boot_order",
    "bink2.auto_boot_discovered",
    "bink2.boot_sequence_selected",
    "bink2.direct_boot_started",
    "bink2.direct_boot_completed",
    "ps_studios_logo.bk2",
    "logo_intro.bk2"
)
foreach($guard in $requiredBootGuards){
    if(-not $hostMovieText.Contains($guard)){
        throw "[V74.0.19] HostMovieBridge boot-sequence capability missing: $guard"
    }
}
$hasLogoIntroLoop=$hostMovieText.Contains("logo_intro_loop.bk2")
if(-not $hasLogoIntroLoop){
    Write-Host "[V74.0.19] WARN: logo_intro_loop.bk2 is not present in the current auto-discovery source; the known-good two-intro sequence remains valid."
}

$agcText=[System.IO.File]::ReadAllText($agc)
foreach($guard in @(
    "SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT",
    "SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS"
)){
    if(-not $agcText.Contains($guard)){throw "[V74.0.19] Required cumulative AGC guard missing: $guard"}
}

$presenterText=[System.IO.File]::ReadAllText($presenter)
foreach($guard in @("SHARPEMU_RENDER_SCALE","ScaleGuestDimension","SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB")){
    if(-not $presenterText.Contains($guard)){throw "[V74.0.19] Presenter cumulative guard missing: $guard"}
}

$nativeText=[System.IO.File]::ReadAllText($nativeWorker)
foreach($guard in @("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE","SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT")){
    if(-not $nativeText.Contains($guard)){throw "[V74.0.19] Native-worker cumulative guard missing: $guard"}
}

Write-Host "[V74.0.19] PRECHECK PASSED."
Write-Host "[V74.0.19] HostMovieBridge auto/direct boot capability verified."
Write-Host "[V74.0.19] Accepted direct intro order: ps_studios_logo.bk2 -> logo_intro.bk2 [-> logo_intro_loop.bk2 when discovered]"
Write-Host "[V74.0.19] V74.0.18 evidence: main loop=18.096s, gather=32.698s, first natural movie only at host t=373.7s."
Write-Host "[V74.0.19] V74.0.18 profile explicitly had bink_auto_boot=0 and grace=900000ms; this package reverses that regression."
Write-Host "[V74.0.19] No new source mutation is required; RUN_3 performs a clean Release build verification."
