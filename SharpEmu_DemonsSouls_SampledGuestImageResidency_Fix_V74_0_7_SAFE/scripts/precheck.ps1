param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root
$payload=Get-PayloadPath

$currentSha=(
    Get-FileHash -LiteralPath $presenter -Algorithm SHA256
).Hash.ToUpperInvariant()

$payloadSha=(
    Get-FileHash -LiteralPath $payload -Algorithm SHA256
).Hash.ToUpperInvariant()

$currentText=[System.IO.File]::ReadAllText($presenter)

$baselineSha="7E2BAF55BE358C248FAC6755DE8C15BA5F2BBB6ACC7BB1F4C3B78CE2F4E7D6E8"
$installedSha="0E1AF87F890A692D288A65026038124CBE1B88976EDBE54857E88612CB23F321"

$baseline=
    $currentSha-eq$baselineSha -and
    $currentText.Contains(
        "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE") -and
    -not $currentText.Contains(
        "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET")

$installed=
    $currentSha-eq$installedSha -and
    $currentText.Contains(
        "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET") -and
    $currentText.Contains(
        "SHARPEMU_V74_0_7_SWAPCHAIN_TEXTURE_STAGING_RETIRE")

if($payloadSha-ne$installedSha){
    throw "[V74.0.7] Package payload SHA changed: $payloadSha"
}

if(-not $baseline -and -not $installed){
    throw (
        "[V74.0.7] Unknown presenter state. " +
        "current_sha=$currentSha expected_baseline=$baselineSha installed=$installedSha"
    )
}

Write-Host "[V74.0.7] PRECHECK PASSED."
Write-Host "[V74.0.7] Presenter=$presenter"
Write-Host "[V74.0.7] current_sha=$currentSha"
Write-Host "[V74.0.7] exact_v7406_3_baseline=$($currentSha-eq$baselineSha)"
Write-Host "[V74.0.7] compute_restore_preserved=$($currentText.Contains('SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE'))"
Write-Host "[V74.0.7] sampled_guest_image_budget_installed=$($currentText.Contains('SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET'))"
Write-Host "[V74.0.7] swapchain_staging_retire_installed=$($currentText.Contains('SHARPEMU_V74_0_7_SWAPCHAIN_TEXTURE_STAGING_RETIRE'))"
Write-Host "[V74.0.7] default_sampled_guest_image_budget_mb=512"
Write-Host "[V74.0.7] already_installed=$installed"
