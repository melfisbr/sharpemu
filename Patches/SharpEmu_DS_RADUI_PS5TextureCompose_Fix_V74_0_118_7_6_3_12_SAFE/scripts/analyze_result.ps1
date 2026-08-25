param()
. (Join-Path $PSScriptRoot 'common.ps1')

$patches=Get-PatchesRoot
$latest=Get-ChildItem -LiteralPath $patches -File -Filter 'SharpEmu_V74_0_118_7_6_3_12_RAD_TEXTURE_UI_*.log' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if($null -eq $latest){
    throw "$script:Tag no V3.12 runtime log found"
}

$lines=[string[]]@(Get-Content -LiteralPath $latest.FullName)

function Count-Simple([string]$Text){
    @($lines|Select-String -SimpleMatch $Text).Count
}
function Count-LinePair([string]$A,[string]$B){
    @($lines|Where-Object{$_ -like "*$A*" -and $_ -like "*$B*"}).Count
}

$nativeSelected=
    (Count-Simple '[BINK-NATIVE][V75.0.0] auto_selected') +
    (Count-Simple 'resolved=native-rad')

$logoRoute=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CAPTURE_ROUTE]' "file='logo_intro_loop.bk2'"
$menuRoute=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CAPTURE_ROUTE]' "file='main_menu.bk2'"

$logoFrame=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_FRAME_READY]' "file='logo_intro_loop.bk2'"
$menuFrame=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_FRAME_READY]' "file='main_menu.bk2'"

$logoImport=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_IMPORT]' "file='logo_intro_loop.bk2'"
$menuImport=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_IMPORT]' "file='main_menu.bk2'"

$logoBind=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_BIND]' "file='logo_intro_loop.bk2'"
$menuBind=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_BIND]' "file='main_menu.bk2'"

$logoPresent=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_GUEST_PRESENT]' "file='logo_intro_loop.bk2'"
$menuPresent=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_GUEST_PRESENT]' "file='main_menu.bk2'"

$logoCloak=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CHILD_CLOAK]' "file='logo_intro_loop.bk2'"
$menuCloak=Count-LinePair '[V74.0.118.7.6.3.12][RAD_UI_CHILD_CLOAK]' "file='main_menu.bk2'"

$logoDescriptorlessDirect=Count-LinePair 'bink2.descriptorless_direct_frame' "file='logo_intro_loop.bk2'"
$menuDescriptorlessDirect=Count-LinePair 'bink2.descriptorless_direct_frame' "file='main_menu.bk2'"

$logoNeutral=Count-LinePair '[V74.0.118.4][RAD_UI_NEUTRAL_FRAME]' "file='logo_intro_loop.bk2'"
$menuNeutral=Count-LinePair '[V74.0.118.4][RAD_UI_NEUTRAL_FRAME]' "file='main_menu.bk2'"

$logoLegacyRegion=Count-LinePair '[V74.0.111][RAD_INTERACTIVE_REGION]' "file='logo_intro_loop.bk2'"
$menuLegacyRegion=Count-LinePair '[V74.0.111][RAD_INTERACTIVE_REGION]' "file='main_menu.bk2'"

$legacyDirect=
    (Count-Simple '[V74.0.118.7.5][RAD_MAIN_MENU_DIRECT_BG_PRESENT]') +
    (Count-Simple '[V74.0.118.7.6.3.10][RAD_MAIN_MENU_SINGLE_SCANOUT_UI_COMPOSITE]')

$summary=[ordered]@{
    version='V74.0.118.7.6.3.12'
    runtime_log=$latest.FullName
    device_lost_count=((Count-Simple 'ErrorDeviceLost')+(Count-Simple 'Vulkan device lost'))
    nihav_ui_attach_count=((Count-Simple 'Bink2 NIHAV bridge attached: logo_intro_loop.bk2')+(Count-Simple 'Bink2 NIHAV bridge attached: main_menu.bk2'))
    native_rad_selected_count=$nativeSelected
    logo_texture_route_count=$logoRoute
    menu_texture_route_count=$menuRoute
    logo_capture_frame_count=$logoFrame
    menu_capture_frame_count=$menuFrame
    logo_capture_import_count=$logoImport
    menu_capture_import_count=$menuImport
    logo_capture_bind_count=$logoBind
    menu_capture_bind_count=$menuBind
    logo_guest_present_count=$logoPresent
    menu_guest_present_count=$menuPresent
    logo_child_cloak_count=$logoCloak
    menu_child_cloak_count=$menuCloak
    ui_descriptorless_keep_guest_count=(Count-Simple '[V74.0.118.7.6.3.12][RAD_UI_DESCRIPTORLESS_KEEP_GUEST]')
    logo_descriptorless_direct_count=$logoDescriptorlessDirect
    menu_descriptorless_direct_count=$menuDescriptorlessDirect
    logo_neutral_frame_count=$logoNeutral
    menu_neutral_frame_count=$menuNeutral
    logo_legacy_region_count=$logoLegacyRegion
    menu_legacy_region_count=$menuLegacyRegion
    legacy_direct_composite_count=$legacyDirect
    delete_tab_count=(Count-Simple '[V74.0.118.7.6.3.8][RAD_TASKBAR_DELETE_TAB]')
}

$summary['classification']=
    if($summary.device_lost_count -gt 0){'device-lost'}
    elseif($summary.nihav_ui_attach_count -gt 0){'unexpected-nihav-ui'}
    elseif($summary.native_rad_selected_count -gt 0){'native-rad-in-process-active-visual-verification-required'}
    elseif($summary.logo_texture_route_count -eq 0){'logo-texture-capture-route-not-active'}
    elseif($summary.menu_texture_route_count -eq 0){'menu-texture-capture-route-not-active'}
    elseif($summary.logo_capture_frame_count -eq 0){'logo-rad-capture-not-ready'}
    elseif($summary.menu_capture_frame_count -eq 0){'menu-rad-capture-not-ready'}
    elseif($summary.logo_capture_bind_count -eq 0){'logo-capture-not-bound-to-guest-yuv'}
    elseif($summary.menu_capture_bind_count -eq 0){'menu-capture-not-bound-to-guest-yuv'}
    elseif($summary.logo_guest_present_count -eq 0){'logo-guest-present-handoff-not-confirmed'}
    elseif($summary.menu_guest_present_count -eq 0){'menu-guest-present-handoff-not-confirmed'}
    elseif(($summary.logo_descriptorless_direct_count+$summary.menu_descriptorless_direct_count) -gt 0){'ui-exclusive-direct-fallback-regressed'}
    elseif(($summary.logo_neutral_frame_count+$summary.menu_neutral_frame_count) -gt 0){'neutral-frame-regressed'}
    elseif(($summary.logo_legacy_region_count+$summary.menu_legacy_region_count) -gt 0){'legacy-child-window-region-regressed'}
    elseif($summary.legacy_direct_composite_count -gt 0){'legacy-direct-compositor-regressed'}
    else{'official-rad-texture-guest-shader-path-active-visual-verification-required'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryPath=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_SUMMARY_$stamp.txt"
$evidencePath=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_RAD_TEXTURE_EVIDENCE_$stamp.txt"

$summary.GetEnumerator() |
    ForEach-Object{"$($_.Key)=$($_.Value)"} |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8

$lines | Where-Object{
    $_ -like '*[V74.0.118.7.6.3.12][RAD_UI_*' -or
    $_ -like '*bink2.descriptorless_direct_frame*logo_intro_loop.bk2*' -or
    $_ -like '*bink2.descriptorless_direct_frame*main_menu.bk2*' -or
    $_ -like '*RAD_UI_NEUTRAL_FRAME*logo_intro_loop.bk2*' -or
    $_ -like '*RAD_UI_NEUTRAL_FRAME*main_menu.bk2*' -or
    $_ -like '*RAD_INTERACTIVE_REGION*logo_intro_loop.bk2*' -or
    $_ -like '*RAD_INTERACTIVE_REGION*main_menu.bk2*' -or
    $_ -like '*RAD_MAIN_MENU_DIRECT_BG_PRESENT*' -or
    $_ -like '*RAD_MAIN_MENU_SINGLE_SCANOUT_UI_COMPOSITE*' -or
    $_ -like '*BINK-NATIVE*'
}|Set-Content -LiteralPath $evidencePath -Encoding UTF8

$items=@($latest.FullName,$summaryPath,$evidencePath)
foreach($pattern in @(
    'SharpEmu_V74_0_118_7_6_3_12_PRECHECK_*.txt',
    'SharpEmu_V74_0_118_7_6_3_12_BUILD_*.log')){
    $item=Get-ChildItem -LiteralPath $patches -File -Filter $pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if($null -ne $item){$items += $item.FullName}
}
if(Test-Path -LiteralPath (Get-StatePath)){
    $items += (Get-StatePath)
}

$resultZip=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_RESULT_$stamp.zip"
Compress-Archive -LiteralPath $items -DestinationPath $resultZip -Force

$summary.GetEnumerator()|ForEach-Object{Write-Host "$($_.Key)=$($_.Value)"}
Write-Tag "SUMMARY=$summaryPath"
Write-Tag "RAD_TEXTURE_EVIDENCE=$evidencePath"
Write-Tag "RESULT_ZIP=$resultZip"
