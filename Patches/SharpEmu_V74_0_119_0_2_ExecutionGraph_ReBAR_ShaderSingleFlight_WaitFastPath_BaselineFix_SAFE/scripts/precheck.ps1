param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
Assert-Baseline

$a=Get-AgcSource
$w=Get-GpuWaitRegistrySource
$p=Get-PresenterSource
$h=Get-HostPoolSource
$q=Get-EnvelopeSource
$tmp=Join-Path $env:TEMP ('v1190_precheck_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp -Force|Out-Null
$oa=Join-Path $tmp 'AgcExports.cs'
$op=Join-Path $tmp 'VulkanVideoPresenter.cs'
$oh=Join-Path $tmp 'VulkanHostBufferPool.cs'
$oq=Join-Path $tmp 'Envelope.cs'
try{
    & (Join-Path $PSScriptRoot 'patch_v1190.ps1') `
        -AgcSource $a -PresenterSource $p -HostPoolSource $h -EnvelopeSource $q `
        -OutputAgc $oa -OutputPresenter $op -OutputHostPool $oh -OutputEnvelope $oq
    Assert-V1190Markers $oa $op $oh $oq
}finally{
    if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}
}

$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$ctx=Join-Path $patches "SharpEmu_V74_0_119_0_2_PRECHECK_$stamp.txt"
@(
    'baseline=V118.0.1',
    'v11902_baseline_owner_fix=1',
    "gpu_wait_registry_path=$w",
    "gpu_wait_registry_sha256=$(Get-Sha $w)",
    'baseline_fps=0.6',
    'baseline_draws_per_s=330',
    'baseline_shader_lookups=65536',
    'baseline_shader_address_hits=52155',
    'baseline_compute_pipeline_fast_hits=40287',
    'baseline_graphics_pipeline_fast_hits=12471',
    'baseline_shader_fallbacks=0',
    'baseline_payload_batch_avg=1.09',
    'baseline_private_mb_approx=19024',
    'baseline_direct_global_upload_bytes_sample=42296076508',
    'baseline_detile_total_mb_sample=24666',
    'architecture=execution_graph',
    'shader_singleflight=1',
    'waiter_latched_fastpath=1',
    'resident_shader_reference_fastpath=1',
    'rebar_direct_auto_detect=1',
    'rebar_fallback=exact_v11712',
    'shader_resident_max=1024',
    'v11713_global_residency_effective=0',
    'render_phase_profile=1',
    'normal_payload_cap=18',
    'producer_payload_cap=48',
    'dual_vkqueue=0',
    'queue_order_change=0',
    'submit_change=0',
    'barrier_change=0',
    'image_lifetime_change=0'
)|Set-Content $ctx -Encoding UTF8

Save-State 2 'PRECHECK_PASSED' @{
    agc=$a;agc_sha256=(Get-Sha $a)
    gpu_wait_registry=$w;gpu_wait_registry_sha256=(Get-Sha $w)
    presenter=$p;presenter_sha256=(Get-Sha $p)
    host_pool=$h;host_pool_sha256=(Get-Sha $h)
    envelope=$q;envelope_sha256=(Get-Sha $q)
    precheck=$ctx
}
Write-Tag "PRECHECK PASSED context=$ctx"
