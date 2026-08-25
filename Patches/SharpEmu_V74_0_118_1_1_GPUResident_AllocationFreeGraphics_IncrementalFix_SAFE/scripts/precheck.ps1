param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$p=Get-Presenter
$q=Get-Envelope
$pt=[IO.File]::ReadAllText($p)

if($pt.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){
    throw "$script:Tag V117.15 still installed"
}
if(-not$pt.Contains('SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID')){
    throw "$script:Tag V118.0.1 baseline missing; this repair is incremental"
}
if(-not$pt.Contains('SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE')){
    throw "$script:Tag V117.16 descriptor baseline missing"
}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$tmp=Join-Path $env:TEMP "v11811_precheck_$stamp"
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
try{
    $pf=Join-Path $tmp 'VulkanVideoPresenter.cs'
    $qf=Join-Path $tmp 'DemonsSoulsGpuQueueEnvelope.cs'
    & (Join-Path $PSScriptRoot 'patch_v1181.ps1') `
        -PresenterSource $p `
        -EnvelopeSource $q `
        -OutputPresenter $pf `
        -OutputEnvelope $qf
    Assert-V11811 $pf $qf
}finally{
    if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}
}

$ctx=Join-Path (Get-PatchesRoot) "SharpEmu_V74_0_118_1_1_PRECHECK_$stamp.txt"
@(
    'baseline=V118.0.1_ALREADY_INSTALLED',
    'v11716_descriptor_cache_already_installed=1',
    'incremental_v1181_transforms=7',
    'false_already_applied_guard_fixed=1',
    'allocation_free_graphics_fastpath=1',
    'shader_reference_fastpath=1',
    'exact_collision_compare=1',
    'vkimage_change=0',
    'buffer_content_change=0',
    'queue_change=0',
    'submit_change=0',
    'barrier_change=0',
    'target_fps=60'
)|Set-Content $ctx -Encoding UTF8

Save-State 2 'PRECHECK_PASSED' @{
    presenter=$p
    presenter_sha256=(Get-Sha $p)
    envelope=$q
    envelope_sha256=(Get-Sha $q)
    precheck=$ctx
}
Write-Tag "PRECHECK PASSED context=$ctx"
