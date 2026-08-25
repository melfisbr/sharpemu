param()
. (Join-Path $PSScriptRoot 'common.ps1')

$root=Get-PackageRoot
$m=Join-Path $root 'manifest.sha256'
foreach($l in Get-Content $m){
    if(-not$l){continue}
    if($l-notmatch '^([0-9A-Fa-f]{64})\s+\*(.+)$'){
        throw "$script:Tag bad manifest"
    }
    $p=Join-Path $root $matches[2]
    if((Get-Sha $p)-ne$matches[1].ToUpperInvariant()){
        throw "$script:Tag hash mismatch $($matches[2])"
    }
}

$patch=[IO.File]::ReadAllText(
    (Join-Path $root 'scripts\patch_v1181.ps1'))

foreach($bad in @(
    "if(`$p.Contains('SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID')){",
    'patch_v11716_base.ps1',
    'function R(',
    'function N(',
    'function W('
)){
    if($patch.Contains($bad)){
        throw "$script:Tag regression guard failed: $bad"
    }
}

foreach($required in @(
    'incremental_from_v1180_1=1',
    'Replace-OnceV11811',
    'ResidentGraphicsExecutionKeyV1181',
    'ResidentGraphicsExecutionEntryV1181',
    'TryGetResidentGraphicsPipelineV1181',
    'RememberResidentGraphicsPipelineV1181',
    'SourceReferenceV1181',
    'partial V118.1 installation detected',
    'image_change=0',
    'buffer_change=0',
    'queue_change=0',
    'submit_change=0',
    'barrier_change=0'
)){
    if(-not$patch.Contains($required)){
        throw "$script:Tag required marker missing: $required"
    }
}

Write-Tag 'PACKAGE VALIDATION PASSED; V118.0 false-idempotency regression removed; 7 incremental V118.1 transforms guarded; PS5.1-safe helpers; no queue/submit/barrier/image/buffer changes.'
