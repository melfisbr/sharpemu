param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$presenter=Get-PresenterSource
Assert-Baseline $presenter

$tmp=Join-Path $env:TEMP ('v120_precheck_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
$out=Join-Path $tmp 'VulkanVideoPresenter.cs'
try{
    & (Join-Path $PSScriptRoot 'patch_v120.ps1') -Source $presenter -Output $out
    Assert-V120Markers $out
}finally{
    if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}
}

$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$ctx=Join-Path $patches "SharpEmu_V74_0_120_0_PRECHECK_$stamp.txt"
@(
    "timestamp=$stamp",
    "repo=$(Get-RepositoryRoot)",
    "presenter_sha256=$(Get-Sha $presenter)",
    'baseline=V118.0.1_with_V119_execution_graph_rebar',
    'baseline_fps=0.4',
    'baseline_draws_per_s=200',
    'baseline_cpu_percent=77',
    'baseline_gpu_percent=37',
    'baseline_device_lost=0',
    'observed_draw_renderer_share_percent=29.8_to_61.1',
    'hot_draw_global_shape=262144,262144,262144,1036,1036',
    'global_allocation_lookup=linear_to_binary',
    'readonly_prepare_transient_lists=removed',
    'zero_one_vertex_transient_dictionary_hashset=removed',
    'feedback_linq=removed',
    'structural_layout_string_canonicalization=exact_value_keyed',
    'draw_resource_phase_profile=runtime_enabled',
    'compute_resource_phase_profile=runtime_enabled',
    'vkimage_change=0',
    'texture_lifetime_change=0',
    'buffer_content_change=0',
    'queue_change=0',
    'submit_change=0',
    'barrier_change=0',
    'pair2_change=0',
    'dual_vkqueue=0'
)|Set-Content -LiteralPath $ctx -Encoding UTF8

Save-State 2 'PRECHECK_PASSED' @{
    presenter=$presenter
    presenter_sha256=(Get-Sha $presenter)
    precheck=$ctx
}
Write-Tag "PRECHECK PASSED context=$ctx"
