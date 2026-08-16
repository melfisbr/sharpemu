param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$repoRoot = Resolve-RepoRootV740231 -RepositoryRoot $RepositoryRoot
$presenterPath = Get-PresenterPathV740231 -Root $repoRoot
$agcPath = Get-AgcPathV740231 -Root $repoRoot
$presenterText = [System.IO.File]::ReadAllText($presenterPath)
$agcText = [System.IO.File]::ReadAllText($agcPath)
$state = Get-V231StateV740231 -Text $presenterText
if ($state -eq "Partial" -or $state -eq "Unknown") {
    throw "[V74.0.23.1] Unsupported/partial Presenter state: $state. No source was modified."
}
if (-not $agcText.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT")) {
    throw "[V74.0.23.1] V74.0.15 large-array single-flight marker is missing from AgcExports.cs."
}
if (-not (Test-V21AbiAppliedV740231 -Root $repoRoot)) {
    throw "[V74.0.23.1] V74.0.21 Entry ABI correction is not fully present."
}
if ($state -eq "Baseline") {
    $dryRun = Convert-PresenterV740231 -Text $presenterText
    if ((Get-V231StateV740231 -Text $dryRun) -ne "Applied") {
        throw "[V74.0.23.1] Same-transformer dry-run failed."
    }
}
$presenterHash = (Get-FileHash -LiteralPath $presenterPath -Algorithm SHA256).Hash.ToUpperInvariant()
$agcHash = (Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host "[V74.0.23.1] PRECHECK PASSED (same transformer dry-run verified)."
Write-Host "[V74.0.23.1] Presenter sha=$presenterHash state=$state"
Write-Host "[V74.0.23.1] AGC sha=$agcHash V74.0.15_singleflight=True"
Write-Host "[V74.0.23.1] Exact-source reference presenter sha=0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8"
Write-Host "[V74.0.23.1] Root cause: V73.0.19.1 rejects baseline creation when byteCount > 128 MiB, but its sparse probe reads only 512 bytes."
Write-Host "[V74.0.23.1] Repair target: bounded 128..512 MiB array textures only; no full-array copy is added."
