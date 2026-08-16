param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$native=Get-NativeWorkerPathV74010 $root
$presenter=Get-PresenterPath $root
$presenterPayload=Get-PresenterPayloadV74011

$nativeSha=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant()
$presenterSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
$payloadSha=(Get-FileHash -LiteralPath $presenterPayload -Algorithm SHA256).Hash.ToUpperInvariant()
$presenterText=[System.IO.File]::ReadAllText($presenter)

$semantic=Test-NativeLaneSemanticV740111 -Path $native -ThrowOnFailure

$knownReferenceSha="F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38"
$observedCurrentSha="8E0FE4E3C23860592E29A9A5B2EA5D6AE974D221098D2ABBB31474087124CFC3"

$nativeKnownHash=
    $nativeSha-eq$knownReferenceSha -or
    $nativeSha-eq$observedCurrentSha

if(-not $semantic.Passed){
    throw "[V74.0.11.1] Native lane is not semantically installed."
}

$baseline=$presenterSha-eq"0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"
$installed=
    $presenterSha-eq"B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41" -and
    $presenterText.Contains("SHARPEMU_V74_0_11_NATURAL_BINK_DESCRIPTORLESS_DIRECT_FALLBACK")

if($payloadSha-ne"B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41"){
    throw "[V74.0.11.1] Package presenter payload changed: $payloadSha"
}

if(-not $baseline -and -not $installed){
    throw (
        "[V74.0.11.1] Unknown presenter state. current=$presenterSha " +
        "baseline=0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66 installed=B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41")
}

Write-Host "[V74.0.11.1] PRECHECK PASSED."
Write-Host "[V74.0.11.1] native_lane_sha=$nativeSha"
Write-Host "[V74.0.11.1] native_known_hash=$nativeKnownHash"
Write-Host "[V74.0.11.1] native_semantic_lane=True"
Write-Host "[V74.0.11.1] native_marker=$($semantic.Checks.marker)"
Write-Host "[V74.0.11.1] native_renderer_limiter=$($semantic.Checks.renderer_limiter)"
Write-Host "[V74.0.11.1] native_no_managed_inline=$($semantic.Checks.no_managed_inline)"
Write-Host "[V74.0.11.1] native_dedicated_generic=$($semantic.Checks.dedicated_generic)"
Write-Host "[V74.0.11.1] presenter_sha=$presenterSha"
Write-Host "[V74.0.11.1] exact_v74010_presenter_baseline=$baseline"
Write-Host "[V74.0.11.1] descriptorless_direct_fallback_installed=$installed"
Write-Host "[V74.0.11.1] compute_restore_preserved=$($presenterText.Contains('SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE'))"
Write-Host "[V74.0.11.1] texture_budget_preserved=$($presenterText.Contains('SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET'))"
