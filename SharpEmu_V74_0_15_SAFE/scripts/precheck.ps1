param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74015 $RepositoryRoot
$hostMovie=Get-HostMovieBridgePathV74015 $root
$presenter=Get-PresenterPathV74015 $root
$native=Get-NativeWorkerPathV74015 $root
$agc=Get-AgcPathV74015 $root
$state=Test-CumulativeStateV74015 -HostMovie $hostMovie -Presenter $presenter -Native $native -Agc $agc

if(-not $state.Host){ throw "[V74.0.15] Robust V74.0.13 startup Bink handoff is not installed." }
if(-not $state.Presenter){ throw "[V74.0.15] Required render-scale/texture-cache presenter support is missing." }
if(-not $state.Native){ throw "[V74.0.15] Required cumulative NativeWorker/renderer-resource lane support is missing." }
if(-not $state.Agc){ throw "[V74.0.15] Required V74.0.4/V74.0.5 AGC texture baseline is missing." }

$agcText=[System.IO.File]::ReadAllText($agc)
$alreadyApplied=$agcText.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT")

if(-not $alreadyApplied){
    $fieldAnchor="private static int _v7405LargeTextureSnapshotReuseTraceCount;"
    if(([regex]::Matches($agcText,[regex]::Escape($fieldAnchor))).Count -ne 1){
        throw "[V74.0.15] V74.0.5 field anchor is not unique. Refusing blind patch."
    }

    $textureStart=$agcText.IndexOf("private static bool TryCreateGuestDrawTexture(",[System.StringComparison]::Ordinal)
    if($textureStart -lt 0){ throw "[V74.0.15] TryCreateGuestDrawTexture signature missing." }
    $nextTextureStart=$agcText.IndexOf("private static bool TryCreateGuestDrawTexture(",$textureStart+1,[System.StringComparison]::Ordinal)
    if($nextTextureStart -ge 0){ throw "[V74.0.15] TryCreateGuestDrawTexture signature is not unique." }

    foreach($requiredNeedle in @(
        "var wantsArrayUpload = isArrayed &&",
        "var tiledLayers = new byte[(long)sliceBytes * arrayLayers];",
        "var layered = new byte[totalBytes];",
        "var v7405CacheLargeSnapshot ="
    )){
        if(-not $agcText.Contains($requiredNeedle)){
            throw "[V74.0.15] Required AGC array/snapshot anchor missing: $requiredNeedle"
        }
    }
}

$nativeText=[System.IO.File]::ReadAllText($native)
if(-not $nativeText.Contains("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT")){
    throw "[V74.0.15] Runtime TBB override from V74.0.14 is not installed."
}
if(-not $nativeText.Contains("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE")){
    throw "[V74.0.15] Renderer/resource native-lane marker missing."
}

Write-Host "[V74.0.15] PRECHECK PASSED."
Write-Host "[V74.0.15] AGC sha=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.15] Presenter sha=$((Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.15] NativeWorker sha=$((Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.15] already_applied=$alreadyApplied"
Write-Host "[V74.0.15] V74.0.14 evidence: main loop 31.6748s; no device loss; no Bink natural request."
Write-Host "[V74.0.15] V74.0.14 evidence: 320MB array coincided with alloc2s_mb=5292 and runtime working_mb=10282."
Write-Host "[V74.0.15] Target: single-flight exact large-array snapshots + 500ms reuse; no layer skipping and no fake texture data."
