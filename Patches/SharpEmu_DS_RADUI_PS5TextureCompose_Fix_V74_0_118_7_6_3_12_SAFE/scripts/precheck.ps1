param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$state=Assert-Baseline

$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$report=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_PRECHECK_$stamp.txt"

@(
    "version=$script:Version",
    "already_installed=$($state.Already)",
    "host_before=$script:ExpectedHostApiSha",
    "host_after=$script:PayloadHostApiSha",
    "presenter_before=$script:ExpectedPresenterSha",
    "presenter_after=$script:PayloadPresenterSha",
    "partial_preserved=$script:ExpectedPartialSha",
    "shader_preserved=$script:ExpectedShaderSha",
    "ampr_preserved=$script:ExpectedAmprSha",
    'normal_ui_binks=logo_intro_loop.bk2;main_menu.bk2;main_menu_ngp.bk2',
    'decoder_priority=native-rad-if-licensed-adapter-present;otherwise-official-external-rad',
    'external_rad_role=decoder-and-texture-source-only',
    'external_child_role=bootstrap-visible-then-empty-region',
    'movie_binding=guest-yuv-textures',
    'final_owner=guest-vulkan-swapchain',
    'neutral_frame_normal_path=disabled',
    'descriptorless_direct_ui_fallback=disabled',
    'legacy_v1187_direct_bg_composite=disabled'
)|Set-Content -LiteralPath $report -Encoding UTF8

Write-Tag "PRECHECK=$report"
Write-Tag 'PRECHECK PASSED. source_write=0'
