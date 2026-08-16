param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root
$payload=Get-PayloadPath

$currentSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
$payloadSha=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToUpperInvariant()
$currentText=[System.IO.File]::ReadAllText($presenter)

$baselineSha="1D8EE63DCB2F4E2A1EEC595535F40224FBE06E1DD16531233597F24740A02A28"
$installedSha="0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"

$baseline=
    $currentSha-eq$baselineSha -and
    $currentText.Contains("SHARPEMU_V74_0_7_1_INVALIDATE_API_REPAIR") -and
    $currentText.Contains("SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE") -and
    -not $currentText.Contains("SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET")

$installed=
    $currentSha-eq$installedSha -and
    $currentText.Contains("SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET") -and
    $currentText.Contains("SHARPEMU_V74_0_8_TEXTURE_RESOURCE_RESIDENCY") -and
    $currentText.Contains("SHARPEMU_V74_0_8_1_FULL_RUNTIME_MEMORY_TRUTH")

if($payloadSha-ne$installedSha){
    throw "[V74.0.8.1] Package payload SHA changed: $payloadSha"
}

if(-not $baseline -and -not $installed){
    throw (
        "[V74.0.8.1] Unknown presenter state. " +
        "current=$currentSha baseline=$baselineSha installed=$installedSha"
    )
}

Write-Host "[V74.0.8.1] PRECHECK PASSED."
Write-Host "[V74.0.8.1] Presenter=$presenter"
Write-Host "[V74.0.8.1] current_sha=$currentSha"
Write-Host "[V74.0.8.1] exact_v7407_1_baseline=$($currentSha-eq$baselineSha)"
Write-Host "[V74.0.8.1] compute_restore_preserved=$($currentText.Contains('SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE'))"
Write-Host "[V74.0.8.1] sampled_guest_image_budget_preserved=$($currentText.Contains('SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET'))"
Write-Host "[V74.0.8.1] standalone_texture_byte_budget_installed=$($currentText.Contains('SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET'))"
Write-Host "[V74.0.8.1] default_standalone_texture_budget_mb=768"
Write-Host "[V74.0.8.1] already_installed=$installed"

Write-Host "[V74.0.8.1] full_runtime_truth_installed=$($currentText.Contains('SHARPEMU_V74_0_8_1_FULL_RUNTIME_MEMORY_TRUTH'))"
