param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74014 $RepositoryRoot
$hostMovie=Get-HostMovieBridgePathV74014 $root
$presenter=Get-PresenterPathV74014 $root
$native=Get-NativeWorkerPathV74014 $root
$state=Test-CumulativeStateV74014 -HostMovie $hostMovie -Presenter $presenter -Native $native

if(-not $state.Host){
    throw "[V74.0.14] Robust V74.0.13 startup Bink handoff is not installed."
}
if(-not $state.Presenter){
    throw "[V74.0.14] Required V74.0.12+ presenter/cache/render-scale support is missing."
}
if(-not $state.Native){
    throw "[V74.0.14] Native worker source is missing the renderer/resource lane contract or worker declaration."
}

$limiter=Get-NativeWorkerLimiterStateV74014 -Path $native
if($limiter.State -eq 'MissingDeclaration' -or $limiter.State -eq 'UnsupportedDeclaration'){
    throw "[V74.0.14] Unsupported NativeWorker limiter state: $($limiter.State)"
}
if($limiter.Declaration.IsConst){
    throw "[V74.0.14] NativeWorkerMaxConcurrent is const; safe runtime override cannot be installed."
}
if($limiter.State -eq 'LiteralCap' -and $limiter.DefaultCap -notin @(2,8,16,32)){
    throw "[V74.0.14] Unexpected literal NativeWorkerMaxConcurrent=$($limiter.DefaultCap); refusing blind rewrite."
}

$currentHash=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant()
$presenterHash=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host "[V74.0.14] PRECHECK PASSED."
Write-Host "[V74.0.14] NativeWorker current_sha=$currentHash"
Write-Host "[V74.0.14] NativeWorker limiter_state=$($limiter.State) declaration='$($limiter.Declaration.Text.Trim())'"
if($limiter.State -eq 'LiteralCap'){
    Write-Host "[V74.0.14] Existing default cap $($limiter.DefaultCap) will be preserved outside explicit SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT overrides."
}
Write-Host "[V74.0.14] Presenter sha=$presenterHash"
Write-Host "[V74.0.14] Result finding: V74.0.13.2 runtime reported tbb_limit=32 while the runner requested 2."
Write-Host "[V74.0.14] Result finding: texture cache 384MB evicted a 320MB array + active textures immediately before ErrorDeviceLost/HEAP_CORRUPTION."
Write-Host "[V74.0.14] Target profile: render_scale=0.5, TBB override=2, renderer/resource lane=8, standalone texture cache=768MB."
