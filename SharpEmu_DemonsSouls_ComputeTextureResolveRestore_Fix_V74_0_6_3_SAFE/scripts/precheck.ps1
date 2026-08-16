param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot

$presenter=Get-PresenterPath $root
$agc=Get-AgcPath $root
$main=Get-MainPath $root

$agcText=[System.IO.File]::ReadAllText($agc)
$mainText=[System.IO.File]::ReadAllText($main)

if(-not $agcText.Contains(
        "SHARPEMU_V74_0_5_LARGE_TEXTURE_SNAPSHOT_REUSE")){
    throw "[V74.0.6.3] V74.0.5 snapshot-reuse prerequisite missing."
}

if(-not [System.IO.File]::ReadAllText($presenter).Contains(
        "SHARPEMU_V74_0_5_COMPUTE_EXCEPTION_STACK")){
    throw "[V74.0.6.3] V74.0.5 compute-stack prerequisite missing."
}

if(-not $mainText.Contains(
        "SHARPEMU_V74_0_3_4_VEH_HOST_STACK_BYPASS_FIXUP")){
    throw "[V74.0.6.3] V74.0.3.4 FailFast prerequisite missing."
}

$state=Get-ComputePhysicalLineState $presenter

$baselineSha=
    "A9E4F7D3BB6ADF5B2956FD332A9C4EA3E28ADE5F2EBFF42DCD73EBDAFB0BA3F5"

$currentSha=(
    Get-FileHash -LiteralPath $presenter -Algorithm SHA256
).Hash.ToUpperInvariant()

$baseline=
    $currentSha-eq$baselineSha -and
    $state.MarkerCount-eq 1 -and
    $state.RestoreCount-eq 0 -and
    $state.Collapsed

$installed=
    $state.MarkerCount-eq 1 -and
    $state.RestoreCount-eq 1 -and
    -not $state.Collapsed -and
    $state.HostExecutable -and
    $state.ForExecutable -and
    $state.AssignmentExecutable -and
    $state.ResolveExecutable -and
    $state.NullGuardExecutable

if(-not $baseline -and -not $installed){
    throw (
        "[V74.0.6.3] Partial/unknown physical-line state: " +
        "sha=$currentSha marker=$($state.MarkerCount) restore=$($state.RestoreCount) " +
        "collapsed=$($state.Collapsed) host=$($state.HostExecutable) " +
        "for=$($state.ForExecutable) assign=$($state.AssignmentExecutable) " +
        "resolve=$($state.ResolveExecutable) null=$($state.NullGuardExecutable)"
    )
}

Write-Host "[V74.0.6.3] PRECHECK PASSED."
Write-Host "[V74.0.6.3] Presenter=$presenter"
Write-Host "[V74.0.6.3] SHA256=$currentSha"
Write-Host "[V74.0.6.3] exact_v7405_baseline=$($currentSha-eq$baselineSha)"
Write-Host "[V74.0.6.3] marker_line_index=$($state.MarkerIndex)"
Write-Host "[V74.0.6.3] collapsed_physical_line=$($state.Collapsed)"
Write-Host "[V74.0.6.3] host_exec=$($state.HostExecutable)"
Write-Host "[V74.0.6.3] for_exec=$($state.ForExecutable)"
Write-Host "[V74.0.6.3] assign_exec=$($state.AssignmentExecutable)"
Write-Host "[V74.0.6.3] resolve_exec=$($state.ResolveExecutable)"
Write-Host "[V74.0.6.3] null_guard_exec=$($state.NullGuardExecutable)"
Write-Host "[V74.0.6.3] already_installed=$installed"
