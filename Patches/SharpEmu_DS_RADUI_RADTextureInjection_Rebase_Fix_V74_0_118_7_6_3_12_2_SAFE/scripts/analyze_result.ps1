param()
. (Join-Path $PSScriptRoot 'common.ps1')
$patches=Get-PatchesRoot
$latest=Get-ChildItem -LiteralPath $patches -File -Filter 'SharpEmu_V74_0_118_7_6_3_12_2_GUEST_TEXTURE_UI_*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -eq $latest){throw "$script:Tag no V3.12 runtime log found"}
$lines=@(Get-Content -LiteralPath $latest.FullName)
function Count-Simple([string]$Text){@($lines|Select-String -SimpleMatch $Text).Count}
function Count-Pair([string]$A,[string]$B){@($lines|Where-Object{$_.Contains($A) -and $_.Contains($B)}).Count}
$summary=[ordered]@{
 version='V74.0.118.7.6.3.12';runtime_log=$latest.FullName;
 device_lost_count=((Count-Simple 'ErrorDeviceLost')+(Count-Simple 'Vulkan device lost'));
 nihav_ui_attach_count=((Count-Simple 'Bink2 NIHAV bridge attached: logo_intro_loop.bk2')+(Count-Simple 'Bink2 NIHAV bridge attached: main_menu.bk2'));
 texture_source_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_SOURCE]');
 capture_armed_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CAPTURE_ARMED]');
 capture_frame_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CAPTURE_FRAME]');
 capture_import_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CAPTURE_IMPORT]');
 texture_bind_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_BIND]');
 chroma_uv_count=(Count-Pair '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CHROMA]' 'desired=UV swap=False');
 videoout_present_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_VIDEOOUT_PRESENT]');
 present_ready_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_PRESENT_READY]');
 child_cloaked_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CHILD_CLOAKED]');
 descriptorless_suppress_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_DESCRIPTORLESS_SUPPRESS]');
 ui_descriptorless_fallback_start_count=((Count-Pair 'bink2.descriptorless_direct_fallback_start' "file='logo_intro_loop.bk2'")+(Count-Pair 'bink2.descriptorless_direct_fallback_start' "file='main_menu.bk2'"));
 legacy_ui_region_count=((Count-Pair '[V74.0.111][RAD_INTERACTIVE_REGION]' "file='logo_intro_loop.bk2'")+(Count-Pair '[V74.0.111][RAD_INTERACTIVE_REGION]' "file='main_menu.bk2'"));
 neutral_yuv_bind_count=((Count-Pair '[V74.0.118.4][RAD_UI_NEUTRAL_YUV_BIND]' "file='logo_intro_loop.bk2'")+(Count-Pair '[V74.0.118.4][RAD_UI_NEUTRAL_YUV_BIND]' "file='main_menu.bk2'"));
 legacy_single_scanout_composite_count=(Count-Simple '[V74.0.118.7.6.3.10][RAD_MAIN_MENU_SINGLE_SCANOUT_UI_COMPOSITE]');
 legacy_direct_bg_present_count=(Count-Simple '[V74.0.118.7.5][RAD_MAIN_MENU_DIRECT_BG_PRESENT]');
 taskbar_delete_tab_count=(Count-Simple '[V74.0.118.7.6.3.8][RAD_TASKBAR_DELETE_TAB]')
}
$summary['classification']=if($summary.device_lost_count -gt 0){'device-lost'}elseif($summary.nihav_ui_attach_count -gt 0){'unexpected-nihav-ui'}elseif($summary.texture_source_count -lt 2){'v312-rad-texture-source-not-armed-for-both-ui-movies'}elseif($summary.capture_import_count -eq 0){'rad-capture-not-imported'}elseif($summary.texture_bind_count -eq 0){'guest-bink-yuv-bind-not-observed'}elseif($summary.chroma_uv_count -eq 0){'rad-capture-chroma-not-confirmed-uv'}elseif($summary.ui_descriptorless_fallback_start_count -gt 0){'exclusive-descriptorless-fallback-still-active'}elseif($summary.legacy_ui_region_count -gt 0){'legacy-rectangular-ui-region-still-active'}elseif($summary.neutral_yuv_bind_count -gt 0){'legacy-neutral-yuv-still-active'}elseif($summary.legacy_single_scanout_composite_count -gt 0 -or $summary.legacy_direct_bg_present_count -gt 0){'post-videoout-compositor-still-active'}elseif($summary.videoout_present_count -eq 0){'guest-videoout-present-handshake-not-observed'}elseif($summary.child_cloaked_count -eq 0){'guest-present-confirmed-rad-child-not-cloaked'}else{'rad-to-guest-bink-texture-injection-active-visual-verification-required'}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$summaryPath=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_2_SUMMARY_$stamp.txt";$evidencePath=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_2_TEXTURE_EVIDENCE_$stamp.txt"
$summary.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}|Set-Content -LiteralPath $summaryPath -Encoding UTF8
$lines|Where-Object{$_.Contains('[V74.0.118.7.6.3.12][RAD_UI_') -or $_.Contains('bink2.descriptorless_direct_fallback_start') -or $_.Contains('[V74.0.111][RAD_INTERACTIVE_REGION]') -or $_.Contains('[V74.0.118.4][RAD_UI_NEUTRAL_YUV_BIND]') -or $_.Contains('[V74.0.118.7.6.3.10][RAD_MAIN_MENU_SINGLE_SCANOUT_UI_COMPOSITE]') -or $_.Contains('[V74.0.118.7.5][RAD_MAIN_MENU_DIRECT_BG_PRESENT]')}|Set-Content -LiteralPath $evidencePath -Encoding UTF8
$items=@($latest.FullName,$summaryPath,$evidencePath);foreach($pattern in @('SharpEmu_V74_0_118_7_6_3_12_2_ARCH_PRECHECK_*.txt','SharpEmu_V74_0_118_7_6_3_12_2_BUILD_*.log')){$item=Get-ChildItem -LiteralPath $patches -File -Filter $pattern|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($null -ne $item){$items += $item.FullName}}
if(Test-Path -LiteralPath (Get-StatePath)){$items += (Get-StatePath)}
$resultZip=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_2_RESULT_$stamp.zip";Compress-Archive -LiteralPath $items -DestinationPath $resultZip -Force
$summary.GetEnumerator()|ForEach-Object{Write-Host "$($_.Key)=$($_.Value)"};Write-Tag "SUMMARY=$summaryPath";Write-Tag "TEXTURE_EVIDENCE=$evidencePath";Write-Tag "RESULT_ZIP=$resultZip"
