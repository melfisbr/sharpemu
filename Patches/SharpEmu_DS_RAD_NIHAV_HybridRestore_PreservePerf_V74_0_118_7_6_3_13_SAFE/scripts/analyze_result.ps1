param()
. (Join-Path $PSScriptRoot 'common.ps1')

$patches=Get-PatchesRoot
$latest=
    Get-ChildItem `
        -LiteralPath $patches `
        -File `
        -Filter 'SharpEmu_V74_0_118_7_6_3_13_RAD_NIHAV_HYBRID_*.log' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if($null -eq $latest) {
    throw "$script:Tag no V3.13 runtime log found"
}

$lines=@(Get-Content -LiteralPath $latest.FullName)

function Count-Text([string]$Text) {
    @($lines | Select-String -SimpleMatch $Text).Count
}

$summary=[ordered]@{
    version='V74.0.118.7.6.3.13'
    runtime_log=$latest.FullName
    device_lost_count=
        ((Count-Text 'ErrorDeviceLost')+
         (Count-Text 'Vulkan device lost'))
    fatal_managed_av_count=
        (Count-Text 'fatal_managed_access_violation')
    logo_intro_rad_attach_count=
        (Count-Text 'Bink RAD bridge attached: logo_intro.bk2')
    logo_intro_rad_complete_count=
        (Count-Text 'Bink RAD bridge completed: logo_intro.bk2')
    logo_loop_internal_route_count=
        (Count-Text "UI_BINK_INTERNAL] count")
    logo_loop_hybrid_marker_count=
        @($lines |
            Where-Object {
                $_ -like '*RAD_NIHAV_HYBRID_ROUTE*' -and
                $_ -like "*file='logo_intro_loop.bk2'*"
            }).Count
    logo_loop_nihav_attach_count=
        (Count-Text 'Bink2 NIHAV bridge attached: logo_intro_loop.bk2')
    main_menu_hybrid_marker_count=
        @($lines |
            Where-Object {
                $_ -like '*RAD_NIHAV_HYBRID_ROUTE*' -and
                $_ -like "*file='main_menu.bk2'*"
            }).Count
    main_menu_nihav_attach_count=
        (Count-Text 'Bink2 NIHAV bridge attached: main_menu.bk2')
    logo_loop_rad_attach_count=
        (Count-Text 'Bink RAD bridge attached: logo_intro_loop.bk2')
    main_menu_rad_attach_count=
        (Count-Text 'Bink RAD bridge attached: main_menu.bk2')
    ui_rad_interactive_route_count=
        (Count-Text '[V74.0.118.3][UI_BINK_RAD_INTERACTIVE_ROUTE]')
    title_loop_composite_count=
        (Count-Text '[V74.0.81][TITLE_LOOP_PRESS_COMPOSITE]')
    title_loop_reservoir_count=
        (Count-Text '[V74.0.100.1][TITLE_LOOP_RESERVOIR]')
    playback_realtime_reservoir_count=
        @($lines |
            Where-Object {
                $_ -like '*playback_buffers*' -and
                $_ -like '*realtime_reservoir_v109=True*'
            }).Count
    direct_yuv_count=
        (Count-Text '[V74.0.105][UI_BINK_DIRECT_YUV]')
    chroma_repair_count=
        (Count-Text '[V74.0.109][DIRECT_YUV_CHROMA_REPAIR]')
    reference_color_count=
        (Count-Text '[V74.0.110][DIRECT_YUV_REFERENCE_COLOR]')
    deferred_idle_backoff_count=
        (Count-Text '[V74.0.68][DEFERRED_IDLE_BACKOFF]')
    dedicated_wait_drain_count=
        (Count-Text '[V74.0.71][DEDICATED_WAIT_DRAIN]')
    gate_owner_wait_drain_count=
        (Count-Text '[V74.0.72][GATE_OWNER_WAIT_DRAIN]')
    native_lane_count=
        (Count-Text '[V74.0.10][NATIVE_LANE]')
}

$summary['classification']=
    if($summary.device_lost_count -gt 0) {
        'device-lost'
    }
    elseif($summary.logo_intro_rad_attach_count -eq 0) {
        'rad-intro-not-active'
    }
    elseif($summary.logo_loop_nihav_attach_count -eq 0) {
        'logo-loop-nihav-not-active'
    }
    elseif($summary.main_menu_nihav_attach_count -eq 0) {
        'main-menu-nihav-not-active'
    }
    elseif($summary.logo_loop_rad_attach_count -gt 0 -or
           $summary.main_menu_rad_attach_count -gt 0 -or
           $summary.ui_rad_interactive_route_count -gt 0) {
        'ui-rad-route-still-active'
    }
    elseif($summary.title_loop_composite_count -eq 0) {
        'nihav-active-but-guest-ui-composite-not-observed'
    }
    else {
        'rad-intro-nihav-ui-hybrid-active'
    }

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryPath=
    Join-Path $patches (
        "SharpEmu_V74_0_118_7_6_3_13_SUMMARY_$stamp.txt")
$evidencePath=
    Join-Path $patches (
        "SharpEmu_V74_0_118_7_6_3_13_HYBRID_EVIDENCE_$stamp.txt")

$summary.GetEnumerator() |
    ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8

$lines |
    Where-Object {
        $_ -like '*Bink RAD bridge attached: logo_intro.bk2*' -or
        $_ -like '*Bink RAD bridge completed: logo_intro.bk2*' -or
        $_ -like '*UI_BINK_INTERNAL*' -or
        $_ -like '*RAD_NIHAV_HYBRID_ROUTE*' -or
        $_ -like '*Bink2 NIHAV bridge attached: logo_intro_loop.bk2*' -or
        $_ -like '*Bink2 NIHAV bridge attached: main_menu.bk2*' -or
        $_ -like '*TITLE_LOOP_PRESS_COMPOSITE*' -or
        $_ -like '*TITLE_LOOP_RESERVOIR*' -or
        $_ -like '*realtime_reservoir_v109=True*' -or
        $_ -like '*UI_BINK_DIRECT_YUV*' -or
        $_ -like '*DIRECT_YUV_CHROMA_REPAIR*' -or
        $_ -like '*DIRECT_YUV_REFERENCE_COLOR*' -or
        $_ -like '*DEFERRED_IDLE_BACKOFF*' -or
        $_ -like '*DEDICATED_WAIT_DRAIN*' -or
        $_ -like '*GATE_OWNER_WAIT_DRAIN*' -or
        $_ -like '*NATIVE_LANE*'
    } |
    Set-Content -LiteralPath $evidencePath -Encoding UTF8

$items=@(
    $latest.FullName,
    $summaryPath,
    $evidencePath
)

foreach($pattern in @(
    'SharpEmu_V74_0_118_7_6_3_13_PRECHECK_*.txt',
    'SharpEmu_V74_0_118_7_6_3_13_BUILD_*.log')) {
    $item=
        Get-ChildItem `
            -LiteralPath $patches `
            -File `
            -Filter $pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if($null -ne $item) {
        $items += $item.FullName
    }
}

if(Test-Path -LiteralPath (Get-StatePath)) {
    $items += (Get-StatePath)
}

$resultZip=
    Join-Path $patches (
        "SharpEmu_V74_0_118_7_6_3_13_RESULT_$stamp.zip")
Compress-Archive `
    -LiteralPath $items `
    -DestinationPath $resultZip `
    -Force

$summary.GetEnumerator() |
    ForEach-Object {
        Write-Host "$($_.Key)=$($_.Value)"
    }

Write-Tag "SUMMARY=$summaryPath"
Write-Tag "HYBRID_EVIDENCE=$evidencePath"
Write-Tag "RESULT_ZIP=$resultZip"
