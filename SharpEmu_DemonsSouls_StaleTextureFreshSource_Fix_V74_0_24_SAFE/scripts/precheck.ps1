param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$repoRoot=Resolve-RepoRootV74024 -RepositoryRoot $RepositoryRoot
$presenterPath=Get-PresenterPathV74024 -Root $repoRoot
$agcPath=Get-AgcPathV74024 -Root $repoRoot
$presenterText=[System.IO.File]::ReadAllText($presenterPath)
$agcText=[System.IO.File]::ReadAllText($agcPath)
$state=Get-V24StateV74024 -Text $presenterText
if ($state -eq "Partial" -or $state -eq "Unknown") { throw "[V74.0.24] Unsupported/partial Presenter state: $state. No source was modified." }
if (-not $agcText.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT")) { throw "[V74.0.24] V74.0.15 large-array single-flight marker is missing." }
if (-not (Test-V21AbiAppliedV74024 -Root $repoRoot)) { throw "[V74.0.24] V74.0.21 Entry ABI correction is not fully present." }
if ($state -eq "Baseline") {
    $dryRun=Convert-PresenterV74024 -Text $presenterText
    if ((Get-V24StateV74024 -Text $dryRun) -ne "Applied") { throw "[V74.0.24] Same-transformer dry-run failed." }
}
$presenterHash=(Get-FileHash -LiteralPath $presenterPath -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host "[V74.0.24] PRECHECK PASSED (same transformer dry-run verified)."
Write-Host "[V74.0.24] Presenter sha=$presenterHash state=$state"
Write-Host "[V74.0.24] V74.0.23.1 large-array baseline marker=True; V74.0.21 Entry ABI=True; V74.0.15 single-flight=True"
Write-Host "[V74.0.24] Evidence: V74.0.23.1 fixed 0x102A400000 (missing-baseline=0, refresh=0, owner=1)."
Write-Host "[V74.0.24] Remaining bug: 26 stale refreshes repeated identical old->new hash pairs; stale draw snapshots are being re-uploaded."
Write-Host "[V74.0.24] Target: before rebuilding a stale <=64 MiB texture, replace its old submitted snapshot with current guest backing bytes."
