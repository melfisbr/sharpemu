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
$installedSha="1D8EE63DCB2F4E2A1EEC595535F40224FBE06E1DD16531233597F24740A02A28"

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
        "SHARPEMU_V74_0_7_SWAPCHAIN_TEXTURE_STAGING_RETIRE") -and
    $currentText.Contains(
        "SHARPEMU_V74_0_7_1_INVALIDATE_API_REPAIR")

if($payloadSha-ne$installedSha){
    throw "[V74.0.7.1] Package payload SHA changed: $payloadSha"
}

if(-not $baseline -and -not $installed){
    throw (
        "[V74.0.7.1] Unknown presenter state. " +
        "current_sha=$currentSha expected_baseline=$baselineSha installed=$installedSha"
    )
}

Write-Host "[V74.0.7.1] PRECHECK PASSED."
Write-Host "[V74.0.7.1] Presenter=$presenter"
Write-Host "[V74.0.7.1] current_sha=$currentSha"
Write-Host "[V74.0.7.1] exact_v7406_3_baseline=$($currentSha-eq$baselineSha)"
Write-Host "[V74.0.7.1] compute_restore_preserved=$($currentText.Contains('SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE'))"
Write-Host "[V74.0.7.1] sampled_guest_image_budget_installed=$($currentText.Contains('SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET'))"
Write-Host "[V74.0.7.1] swapchain_staging_retire_installed=$($currentText.Contains('SHARPEMU_V74_0_7_SWAPCHAIN_TEXTURE_STAGING_RETIRE'))"
Write-Host "[V74.0.7.1] default_sampled_guest_image_budget_mb=512"
Write-Host "[V74.0.7.1] already_installed=$installed"

Write-Host "[V74.0.7.1] invalidate_api_repair_installed=$($currentText.Contains('SHARPEMU_V74_0_7_1_INVALIDATE_API_REPAIR'))"
