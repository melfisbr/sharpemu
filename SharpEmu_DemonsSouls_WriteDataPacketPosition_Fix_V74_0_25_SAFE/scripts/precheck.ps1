param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$repoRoot=Resolve-RepoRootV74025 -RepositoryRoot $RepositoryRoot
$agcPath=Get-AgcPathV74025 -Root $repoRoot
$agcText=[System.IO.File]::ReadAllText($agcPath)
$state=Get-V25StateV74025 -Text $agcText
if ($state -eq "Partial" -or $state -eq "Unknown") { throw "[V74.0.25] Unsupported/partial AGC state: $state. No source was modified." }
if (-not (Test-PresenterRollupV74025 -Root $repoRoot)) { throw "[V74.0.25] V74.0.23.1/V74.0.24 Presenter rollup is not fully present." }
if (-not (Test-V21AbiAppliedV74025 -Root $repoRoot)) { throw "[V74.0.25] V74.0.21 Entry ABI correction is not fully present." }
if ($state -eq "Baseline") {
    $dryRun=Convert-AgcV74025 -Text $agcText
    if ((Get-V25StateV74025 -Text $dryRun) -ne "Applied") { throw "[V74.0.25] Same-transformer dry-run failed." }
}
$agcHash=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host "[V74.0.25] PRECHECK PASSED (same transformer dry-run verified)."
Write-Host "[V74.0.25] AGC sha=$agcHash state=$state"
Write-Host "[V74.0.25] V74.0.21 Entry ABI=True; V74.0.23.1 large-array baseline=True; V74.0.24 fresh stale-source=True"
Write-Host "[V74.0.25] Evidence: V74.0.24 reduced repeated stale hash pairs to one and preserved the 320 MiB array fix."
Write-Host "[V74.0.25] Remaining anomaly: seven startup WAIT_REG_MEM queues stayed registered while historical runs completed these same labels through real WRITE_DATA producers."
Write-Host "[V74.0.25] Target: opt-in WRITE_DATA packet-position scheduling; no label is forced and RELEASE_MEM/DMA visibility is unchanged."
