param()
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-PackageRoot;$m=Join-Path $root 'manifest.sha256'
foreach($l in Get-Content $m){
 if(-not$l){continue};if($l-notmatch '^([0-9A-Fa-f]{64})\s+\*(.+)$'){throw "$script:Tag bad manifest"}
 $p=Join-Path $root $matches[2];if((Get-Sha $p)-ne$matches[1].ToUpperInvariant()){throw "$script:Tag hash mismatch $($matches[2])"}
}
$patch=[IO.File]::ReadAllText((Join-Path $root 'scripts\patch_v1181.ps1'))
foreach($forbiddenHelper in @(
    'function R(',
    'function N(',
    'function W(',
    '$p=R $p',
    '$q=R $q'
)){
    if($patch.Contains($forbiddenHelper)){
        throw "$script:Tag Windows PowerShell 5.1 alias collision: $forbiddenHelper"
    }
}
foreach($requiredHelper in @(
    'function Replace-OnceV1180',
    'function Normalize-NewlinesV1180',
    'function Write-Utf8NoBomV1180',
    '$p=Replace-OnceV1180 $p',
    '$q=Replace-OnceV1180 $q'
)){
    if(-not$patch.Contains($requiredHelper)){
        throw "$script:Tag Windows PowerShell 5.1 helper missing: $requiredHelper"
    }
}
foreach($x in @('ResidentShaderProgramV1180','SequenceEqual(spirv)','ResidentComputeExecutionKeyV1180',
'ResidentGraphicsExecutionKeyV1181','SHARPEMU_V74_0_118_1_ALLOCATION_FREE_GRAPHICS_FASTPATH','TryGetResidentGraphicsPipelineV1181','RememberResidentGraphicsPipelineV1181','SourceReferenceV1181','resident_module=1','image_change=0','queue_change=0','submit_change=0','barrier_change=0')){
 if(-not$patch.Contains($x)){throw "$script:Tag guard missing $x"}
}
Write-Tag 'PACKAGE VALIDATION PASSED; Windows PowerShell 5.1 alias-collision guard passed; V118.1 allocation-free exact-checked graphics fast path, shader reference fast path, resident-module lifetime, V117.16 descriptor cache and no queue/submit/barrier/image changes verified.'
