. (Join-Path $PSScriptRoot 'common.ps1')
$patches=Get-PatchesRoot
$repo=Get-RepoRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$audit=Join-Path $patches "SharpEmu_V74_0_67_2_16_SOURCE_AUDIT_$stamp.txt"
& (Join-Path $PSScriptRoot 'source_audit.ps1') -OutputPath $audit

if(!(Test-Path -LiteralPath $audit -PathType Leaf)){
    throw '[V74.0.67.2.16] Source audit was not generated.'
}

$txt=[IO.File]::ReadAllText($audit)
$checks=[ordered]@{
    array_lookup=$txt.Contains('agc-array-cache-lookup')
    array_store=$txt.Contains('agc-array-cache-store')
    array_eviction=$txt.Contains('agc-array-cache-eviction')
    slow_wait=$txt.Contains('agc-slow-wait-producer')
    dedicated_wait=$txt.Contains('agc-dedicated-wait-drain')
    gate_owner_wait=$txt.Contains('agc-gate-owner-wait-drain')
    capacity_yield=$txt.Contains('vk-submission-capacity-yield')
    hard_cap_probe=$txt.Contains('vk-inline-hard-cap-probe')
    allocation_inventory=$txt.Contains('ALLOC_SITE_COUNT')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.16] diagnostic_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

if($failed){throw '[V74.0.67.2.16] SOURCE DIAGNOSTIC FAILED.'}

$zip=Join-Path $patches "SharpEmu_V74_0_67_2_16_SOURCE_AUDIT_$stamp.zip"
Compress-Archive -LiteralPath $audit -DestinationPath $zip -Force

Write-Host '[V74.0.67.2.16] DIAGNOSTIC PASSED.'
Write-Host "[V74.0.67.2.16] ResultZip=$zip"
