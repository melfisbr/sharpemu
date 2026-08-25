param()
. (Join-Path $PSScriptRoot 'common.ps1')

$patches=Get-PatchesRoot
$latest=Get-ChildItem -LiteralPath $patches -File `
    -Filter 'SharpEmu_V75_0_1_2_EXTERNAL_RAD_*.log' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if($null -eq $latest){
    throw "$script:Tag no V75.0.1.2 runtime log found"
}

$lines=@(Get-Content -LiteralPath $latest.FullName)

function Count-Simple([string]$Text){
    @($lines|Select-String -SimpleMatch $Text).Count
}

function Count-RadAttach([string]$Movie){
    @(
        $lines |
            Where-Object {
                $_ -like "*Bink RAD bridge attached: $Movie*"
            }
    ).Count
}

$summary=[ordered]@{
    version='V75.0.1.2'
    runtime_log=$latest.FullName
    ps_studios_rad_attach_count=(Count-RadAttach 'ps_studios_logo.bk2')
    attract_rad_attach_count=(Count-RadAttach 'attract_movie.bk2')
    logo_intro_rad_attach_count=(Count-RadAttach 'logo_intro.bk2')
    logo_loop_rad_attach_count=(Count-RadAttach 'logo_intro_loop.bk2')
    main_menu_rad_attach_count=(Count-RadAttach 'main_menu.bk2')
    native_auto_selected_count=(Count-Simple '[BINK-NATIVE][V75.0.0] auto_selected')
    native_open_failed_count=(Count-Simple '[BINK-NATIVE][V75.0.0] open_failed')
    native_attach_failed_count=(Count-Simple '[BINK-NATIVE][V75.0.0] attach_failed')
    rad_required_missing_count=(Count-Simple 'bink2.rad_required_missing')
    device_lost_count=((Count-Simple 'ErrorDeviceLost')+(Count-Simple 'Vulkan device lost'))
}

$radTotal=
    $summary.ps_studios_rad_attach_count +
    $summary.attract_rad_attach_count +
    $summary.logo_intro_rad_attach_count +
    $summary.logo_loop_rad_attach_count +
    $summary.main_menu_rad_attach_count

$summary['external_rad_total_attach_count']=$radTotal
$summary['classification']=
    if($summary.device_lost_count -gt 0){
        'device-lost'
    }elseif($summary.native_auto_selected_count -gt 0 -or
            $summary.native_open_failed_count -gt 0 -or
            $summary.native_attach_failed_count -gt 0){
        'v75-native-route-still-active'
    }elseif($summary.rad_required_missing_count -gt 0){
        'external-rad-path-missing'
    }elseif($summary.ps_studios_rad_attach_count -eq 0){
        'ps-studios-rad-not-restored'
    }elseif($summary.attract_rad_attach_count -eq 0){
        'attract-rad-not-restored'
    }elseif($summary.logo_intro_rad_attach_count -eq 0){
        'logo-intro-rad-not-restored'
    }elseif($summary.main_menu_rad_attach_count -eq 0){
        'main-menu-rad-not-restored'
    }else{
        'external-rad-pre-v75-route-restored'
    }

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryPath=Join-Path $patches "SharpEmu_V75_0_1_2_RAD_RESTORE_SUMMARY_$stamp.txt"
$evidencePath=Join-Path $patches "SharpEmu_V75_0_1_2_RAD_RESTORE_EVIDENCE_$stamp.txt"

$summary.GetEnumerator() |
    ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8

$lines |
    Where-Object {
        $_ -like '*Bink RAD bridge attached:*' -or
        $_ -like '*[BINK-NATIVE][V75.0.0]*' -or
        $_ -like '*bink2.rad_required_missing*' -or
        $_ -like '*RAD_RUNTIME_AUTO_PATH*'
    } |
    Set-Content -LiteralPath $evidencePath -Encoding UTF8

$items=@($latest.FullName,$summaryPath,$evidencePath,(Get-StatePath))
foreach($pattern in @(
    'SharpEmu_V75_0_1_2_RAD_RESTORE_PRECHECK_*.txt',
    'SharpEmu_V75_0_1_2_RAD_RESTORE_BUILD_*.log'
)){
    $item=Get-ChildItem -LiteralPath $patches -File -Filter $pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if($null -ne $item){
        $items += $item.FullName
    }
}

$resultZip=Join-Path $patches "SharpEmu_V75_0_1_2_RAD_RESTORE_RESULT_$stamp.zip"
Compress-Archive -LiteralPath $items -DestinationPath $resultZip -Force

$summary.GetEnumerator() |
    ForEach-Object { Write-Host "$($_.Key)=$($_.Value)" }

Write-Tag "SUMMARY=$summaryPath"
Write-Tag "EVIDENCE=$evidencePath"
Write-Tag "RESULT_ZIP=$resultZip"
