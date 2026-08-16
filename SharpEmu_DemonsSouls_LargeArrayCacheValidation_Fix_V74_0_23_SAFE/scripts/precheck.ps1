param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$repoRoot = Resolve-RepoRootV74023 -RepositoryRoot $RepositoryRoot
$agcPath = Get-AgcPathV74023 -Root $repoRoot
$agcText = [System.IO.File]::ReadAllText($agcPath)
$state = Get-V23StateV74023 -Text $agcText
if ($state -eq "Partial" -or $state -eq "Unknown") {
    throw "[V74.0.23] Unsupported/partial AGC state: $state. No source was modified."
}
if (-not (Test-V21AbiAppliedV74023 -Root $repoRoot)) {
    throw "[V74.0.23] V74.0.21 Entry ABI/_init_env correction is not fully present."
}
if ($state -eq "Baseline") {
    $dryRun = Convert-AgcV74023 -Text $agcText
    if ((Get-V23StateV74023 -Text $dryRun) -ne "Applied") {
        throw "[V74.0.23] Dry-run transformer did not reach Applied state."
    }
}
$agcHash = (Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
Write-Host "[V74.0.23] PRECHECK PASSED (same transformer dry-run verified)."
Write-Host "[V74.0.23] AGC sha=$agcHash"
Write-Host "[V74.0.23] state=$state"
Write-Host "[V74.0.23] V74.0.21 EntryParams/_init_env correction verified."
Write-Host "[V74.0.23] V74.0.22: main loop 17.0443s; first frame 3840x2160; no natural Bink in 173.95s."
Write-Host "[V74.0.23] V74.0.22: 0x102A400000 logged 26 missing-baseline refreshes; 320MiB each; ARRAY_SINGLEFLIGHT reuse counter reached 384."
Write-Host "[V74.0.23] Target: stop repeated re-materialization only when exact >=64MiB array identity is already resident and CPU write tracker is clean."
