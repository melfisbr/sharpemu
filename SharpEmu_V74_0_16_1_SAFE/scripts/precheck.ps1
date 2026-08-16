param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74015 $RepositoryRoot
$hostMovie=Get-HostMovieBridgePathV74015 $root
$presenter=Get-PresenterPathV74015 $root
$nativeWorker=Get-NativeWorkerPathV74015 $root
$agc=Get-AgcPathV74015 $root
$state=Test-CumulativeStateV74015 -HostMovie $hostMovie -Presenter $presenter -Native $nativeWorker -Agc $agc

if(-not $state.Host){ throw "[V74.0.16.1] Robust startup Bink handoff baseline is missing." }
if(-not $state.Presenter){ throw "[V74.0.16.1] Required presenter cache/render-scale support is missing." }
if(-not $state.Native){ throw "[V74.0.16.1] Required native worker/resource lane support is missing." }
if(-not $state.Agc){ throw "[V74.0.16.1] Required V74.0.4/V74.0.5 AGC baseline is missing." }

$agcText=[System.IO.File]::ReadAllText($agc)
if(-not $agcText.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT")){
    throw "[V74.0.16.1] V74.0.15 large-array single-flight is not installed."
}

$alreadyApplied=$agcText.Contains("SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY")
if($alreadyApplied){
    foreach($installedGuard in @(
        "TryUseV74016DccAlias",
        "RememberV74016DccAlias",
        "_v74016LargeSnapshotReuseTtlMs",
        "unchecked(v7405Now - v7405Cached.Tick) <= _v74016LargeSnapshotReuseTtlMs)",
        "unchecked(v7405Now - entry.Value.Tick) > _v74016LargeSnapshotReuseTtlMs)"
    )){
        if(-not $agcText.Contains($installedGuard)){
            throw "[V74.0.16.1] Partial/inconsistent prior V74.0.16.1 state: missing $installedGuard"
        }
    }
}
if(-not $alreadyApplied){
    $dccFieldAnchor="private static int _dccAliasTraceCount;"
    if(([regex]::Matches($agcText,[regex]::Escape($dccFieldAnchor))).Count -ne 1){
        throw "[V74.0.16.1] DCC alias field anchor is not unique."
    }
    $resolverSignature="private static bool TryResolveDccMetadataAlias("
    if(([regex]::Matches($agcText,[regex]::Escape($resolverSignature))).Count -ne 1){
        throw "[V74.0.16.1] TryResolveDccMetadataAlias signature is not unique."
    }
    $snapshotField="private static int _v7405LargeTextureSnapshotReuseTraceCount;"
    if(([regex]::Matches($agcText,[regex]::Escape($snapshotField))).Count -ne 1){
        throw "[V74.0.16.1] V74.0.5 snapshot field anchor is not unique."
    }
    foreach($needle in @(
        "metadataMatches = 0",
        "drawState.KnownRenderTargets.Values",
        "GuestGpu.Current.IsGpuGuestImageAvailable("
    )){
        if(-not $agcText.Contains($needle)){
            throw "[V74.0.16.1] Structural prerequisite missing: $needle"
        }
    }
    $resolverSignature="private static bool TryResolveDccMetadataAlias("
    $resolverIndex=$agcText.IndexOf($resolverSignature,[System.StringComparison]::Ordinal)
    $resolverOpenBrace=$agcText.IndexOf('{',$resolverIndex)
    if($resolverIndex -lt 0 -or $resolverOpenBrace -lt 0){
        throw "[V74.0.16.1] DCC resolver structural extraction failed."
    }
    $resolverDepth=0
    $resolverEnd=-1
    for($resolverCharIndex=$resolverOpenBrace;$resolverCharIndex -lt $agcText.Length;$resolverCharIndex++){
        $resolverCharacter=$agcText[$resolverCharIndex]
        if($resolverCharacter -eq '{'){$resolverDepth++}
        elseif($resolverCharacter -eq '}'){
            $resolverDepth--
            if($resolverDepth -eq 0){$resolverEnd=$resolverCharIndex+1;break}
        }
    }
    if($resolverEnd -lt 0){
        throw "[V74.0.16.1] DCC resolver brace scan failed during precheck."
    }
    $resolverText=$agcText.Substring($resolverIndex,$resolverEnd-$resolverIndex)
    $resultAnchor=Get-V740161DccResultReasonAnchor -ResolverText $resolverText
    if($resultAnchor.Start -lt 0){
        throw "[V74.0.16.1] DCC semantic result anchor rejected during precheck."
    }
    $ttlHitPattern='unchecked\s*\(\s*v7405Now\s*-\s*v7405Cached\.Tick\s*\)\s*<=\s*2000\s*\)'
    $ttlEvictPattern='unchecked\s*\(\s*v7405Now\s*-\s*entry\.Value\.Tick\s*\)\s*>\s*2000\s*\)'
    if(([regex]::Matches($agcText,$ttlHitPattern)).Count -ne 1 -or
       ([regex]::Matches($agcText,$ttlEvictPattern)).Count -ne 1){
        throw "[V74.0.16.1] V74.0.5 2-second TTL structure is not unique."
    }
}

Write-Host "[V74.0.16.1] PRECHECK PASSED (DCC semantic result anchor verified)."
Write-Host "[V74.0.16.1] AGC sha=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.16.1] already_applied=$alreadyApplied"
Write-Host "[V74.0.16.1] V74.0.15 evidence: array owner=1 reuse=15 saved=4800MB; max alloc/2s fell 5292 -> 850MB."
Write-Host "[V74.0.16.1] V74.0.15 evidence: peak working/private about 8013/12352MB; no DeviceLost/heap corruption."
Write-Host "[V74.0.16.1] Remaining symptom: no natural Bink in 241s; repeated unresolved DCC samples still fall back."
Write-Host "[V74.0.16.1] Target: short-lived verified GPU-resident DCC alias history + longer write-generation-safe non-DCC snapshot reuse."
