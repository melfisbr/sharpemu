param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$p=Get-Presenter;$q=Get-Envelope
$pt=[IO.File]::ReadAllText($p);$qt=[IO.File]::ReadAllText($q)
if($pt.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){throw "$script:Tag V117.15 still installed"}
if(-not$pt.Contains('SHARPEMU_V74_0_117_14_PRODUCER_ITEM_HEADROOM')){throw "$script:Tag V117.14 baseline missing"}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$tmp=Join-Path $env:TEMP "v1180_$stamp";New-Item -ItemType Directory $tmp|Out-Null
try{
 $p16=Join-Path $tmp 'p16.cs';$q16=Join-Path $tmp 'q16.cs'
 & (Join-Path $PSScriptRoot 'patch_v11716_base.ps1') -PresenterSource $p -EnvelopeSource $q -OutputPresenter $p16 -OutputEnvelope $q16
 $pf=Join-Path $tmp 'pf.cs';$qf=Join-Path $tmp 'qf.cs'
 & (Join-Path $PSScriptRoot 'patch_v1180.ps1') -PresenterSource $p16 -EnvelopeSource $q16 -OutputPresenter $pf -OutputEnvelope $qf
 Assert-V1180 $pf $qf
}finally{Remove-Item $tmp -Recurse -Force}
$ctx=Join-Path (Get-PatchesRoot) "SharpEmu_V74_0_118_0_1_PRECHECK_$stamp.txt"
@('baseline=V117.14_after_V11715_rollback','includes_v11716_descriptor_cache=1','resident_shader_id=1',
'exact_spirv_content_guard=1','resident_shader_module=1','direct_pipeline_fastpath=1','max_resident_shaders=4096',
'vkimage_change=0','buffer_content_change=0','queue_change=0','submit_change=0','barrier_change=0',
'target_fps=60')|Set-Content $ctx -Encoding UTF8
Save-State 2 'PRECHECK_PASSED' @{presenter=$p;presenter_sha256=(Get-Sha $p);envelope=$q;envelope_sha256=(Get-Sha $q);precheck=$ctx}
Write-Tag "PRECHECK PASSED $ctx"
