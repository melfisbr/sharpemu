param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$native=Get-NativeWorkerPathV74010 $root
$presenter=Get-PresenterPath $root
$hostMovie=Get-HostMovieBridgePathV74012 $root

$nativeSemantic=Test-NativeLaneSemanticV740111 -Path $native -ThrowOnFailure
$presenterSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
$presenterText=[System.IO.File]::ReadAllText($presenter)
$hostState=Test-StartupBinkHandoffStateV74012 $hostMovie

$presenterBaseline=$presenterSha-eq"1F4D6BF5B71AC0B773052D0FFC9C267CF8C9A0CD3868A33E5368FE8F828088CA"
$presenterInstalled=
    $presenterSha-eq"B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245" -and
    $presenterText.Contains("SHARPEMU_V74_0_12_BINK_COMPLETION_VISUAL_RELEASE")

if(-not $presenterBaseline -and -not $presenterInstalled){
    throw "[V74.0.12] Unexpected presenter SHA: $presenterSha"
}

if(-not $hostState.Baseline -and -not $hostState.Installed){
    throw "[V74.0.12] HostMovieBridge takeover contract changed."
}

Write-Host "[V74.0.12] PRECHECK PASSED."
Write-Host "[V74.0.12] native_semantic_lane=True"
Write-Host "[V74.0.12] presenter_sha=$presenterSha"
Write-Host "[V74.0.12] exact_v74011_2_presenter_baseline=$presenterBaseline"
Write-Host "[V74.0.12] presenter_fastboot_handoff_installed=$presenterInstalled"
Write-Host "[V74.0.12] host_movie_baseline=$($hostState.Baseline)"
Write-Host "[V74.0.12] host_startup_completion_installed=$($hostState.Installed)"
Write-Host "[V74.0.12] one_shot_movies=ps_studios_logo.bk2,logo_intro.bk2"
Write-Host "[V74.0.12] logo_intro_loop_completion_shim=False"
Write-Host "[V74.0.12] runtime_trace_policy=low-overhead"
