param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root
$currentSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
$text=[System.IO.File]::ReadAllText($presenter)

if($currentSha-ne"0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"){
    throw "[V74.0.9] Presenter SHA mismatch. current=$currentSha expected=0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"
}

foreach($marker in @(
    "SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET",
    "SHARPEMU_V74_0_8_1_FULL_RUNTIME_MEMORY_TRUTH",
    "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET",
    "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE"
)){
    if(-not $text.Contains($marker)){
        throw "[V74.0.9] Required accumulated marker missing: $marker"
    }
}

Write-Host "[V74.0.9] PRECHECK PASSED."
Write-Host "[V74.0.9] Presenter=$presenter"
Write-Host "[V74.0.9] SHA256=$currentSha"
Write-Host "[V74.0.9] source_changes=None"
Write-Host "[V74.0.9] compute_restore=True"
Write-Host "[V74.0.9] texture_budget=True"
Write-Host "[V74.0.9] full_runtime_truth=True"
Write-Host "[V74.0.9] targeted_45D_trace=0x000000045D550000"
Write-Host "[V74.0.9] max_horizon_seconds=600"
Write-Host "[V74.0.9] V73.18 natural-Bink reference horizon=~479.5s"
