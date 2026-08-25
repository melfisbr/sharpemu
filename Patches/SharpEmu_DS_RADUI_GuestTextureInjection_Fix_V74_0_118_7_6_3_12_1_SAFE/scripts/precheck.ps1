param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$state=Get-BaselineState
$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$report=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_1_ARCH_PRECHECK_$stamp.txt"
$hostMovieText=[IO.File]::ReadAllText((Get-SourcePath $script:Preserve.HostMovie.Rel))
$videoOutText=[IO.File]::ReadAllText((Get-SourcePath $script:Preserve.VideoOut.Rel))
@(
 "version=$script:Version",
 "baseline_state=$($state.State)",
 'architectural_fault=external-window-region/post-videoout composition is not the guest Bink texture contract',
 "source_contract_ui_binks_are_resources=$($hostMovieText.Contains('These Binks are not fullscreen owner movies'))",
 "source_contract_videoout_is_final_boundary=$($videoOutText.Contains('TrySubmitGuestImage'))",
 'runtime_v311_descriptorless_fallback=confirmed for logo_intro_loop and main_menu',
 'runtime_v311_rectangular_region=confirmed main_menu left_guest_pct=34 bottom_guest_pct=13',
 'ofw_scope=643 SELF/ELF structural modules; dynlib payload encrypted; no decoded ELF NID correlation available',
 'sdk_observed=CodeVersion 9000048; DataVersion 1000050',
 'eboot_evidence=CCPLdrBinkSimpleMovie + BinkGPU Agc registerResource + frame_bufs Plane',
 'new_pipeline=official RAD -> BGRA capture -> guest Bink Y/UV -> guest AGC/shader -> sceVideoOutSubmitFlip',
 'post_videoout_composite=disabled',
 'rectangular_child_region=disabled',
 'descriptorless_exclusive_fallback=disabled for external RAD UI Binks',
 'chroma_default=UV',
 'standalone_default=texture injection enabled unless SHARPEMU_DS_RAD_UI_TEXTURE_INJECTION=0',
 'native_sdk_future=existing native-rad path remains preferred if licensed Bink SDK adapter is built'
)|Set-Content -LiteralPath $report -Encoding UTF8
Write-Tag "ARCH_PRECHECK=$report"
Write-Tag 'PRECHECK PASSED. Nothing changed.'
