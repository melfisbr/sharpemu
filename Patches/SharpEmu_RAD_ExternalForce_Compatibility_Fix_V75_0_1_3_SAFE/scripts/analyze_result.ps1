param()
. (Join-Path $PSScriptRoot 'common.ps1')
$patches=Get-PatchesRoot
$latest=Get-ChildItem -LiteralPath $patches -File -Filter 'SharpEmu_V75_0_1_3_EXTERNAL_RAD_*.log'|
    Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -eq $latest){throw "$script:Tag no V75.0.1.3 runtime log found"}
$lines=@(Get-Content -LiteralPath $latest.FullName)
function Count-Simple([string]$Text){@($lines|Select-String -SimpleMatch $Text).Count}
function Count-Pair([string]$A,[string]$B){@($lines|Where-Object{$_ -like "*$A*" -and $_ -like "*$B*"}).Count}

$summary=[ordered]@{
    version='V75.0.1.3'
    runtime_log=$latest.FullName
    rad_bridge_attach_count=(Count-Simple '[LOADER][INFO] Bink RAD bridge attached:')
    ps_studios_rad_count=(Count-Pair 'Bink RAD bridge attached:' 'ps_studios_logo.bk2')
    attract_rad_count=(Count-Pair 'Bink RAD bridge attached:' 'attract_movie.bk2')
    logo_intro_rad_count=(Count-Pair 'Bink RAD bridge attached:' 'logo_intro.bk2')
    logo_loop_rad_count=(Count-Pair 'Bink RAD bridge attached:' 'logo_intro_loop.bk2')
    main_menu_rad_count=(Count-Pair 'Bink RAD bridge attached:' 'main_menu.bk2')
    native_adapter_loaded_count=(Count-Simple '[BINK-NATIVE][V75.0.0] adapter_loaded')
    native_auto_selected_count=(Count-Simple '[BINK-NATIVE][V75.0.0] auto_selected')
    native_bridge_attached_count=(Count-Simple '[BINK-NATIVE][V75.0.0] bridge_attached')
    native_open_failed_count=(Count-Simple '[BINK-NATIVE][V75.0.0] open_failed')
    native_attach_failed_count=(Count-Simple '[BINK-NATIVE][V75.0.0] attach_failed')
    external_force_count=((Count-Simple '[V75.0.1.3][RAD_EXTERNAL_FORCE]')+(Count-Simple '[V75.0.1.3][RAD_EXTERNAL_FORCE_CASE]'))
    device_lost_count=((Count-Simple 'ErrorDeviceLost')+(Count-Simple 'Vulkan device lost'))
}
$nativeBad=
    $summary.native_adapter_loaded_count +
    $summary.native_auto_selected_count +
    $summary.native_bridge_attached_count +
    $summary.native_open_failed_count +
    $summary.native_attach_failed_count
$summary['classification']=
    if($summary.device_lost_count -gt 0){'device-lost'}
    elseif($nativeBad -gt 0){'native-v75-route-still-observed'}
    elseif($summary.rad_bridge_attach_count -eq 0){'external-rad-not-observed'}
    elseif($summary.main_menu_rad_count -eq 0){'external-rad-active-main-menu-not-observed'}
    else{'official-external-rad-active-native-v75-disabled'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryPath=Join-Path $patches "SharpEmu_V75_0_1_3_SUMMARY_$stamp.txt"
$evidencePath=Join-Path $patches "SharpEmu_V75_0_1_3_RAD_EVIDENCE_$stamp.txt"
$summary.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}|Set-Content -LiteralPath $summaryPath -Encoding UTF8
$lines|Where-Object{
    $_ -like '*Bink RAD bridge attached:*' -or
    $_ -like '*[BINK-NATIVE][V75.0.0]*' -or
    $_ -like '*[V75.0.1.3][RAD_EXTERNAL_FORCE]*'
}|Set-Content -LiteralPath $evidencePath -Encoding UTF8

$items=@($latest.FullName,$summaryPath,$evidencePath)
foreach($pattern in @('SharpEmu_V75_0_1_3_RAD_EXTERNAL_PRECHECK_*.txt','SharpEmu_V75_0_1_3_RAD_EXTERNAL_BUILD_*.log')){
    $item=Get-ChildItem -LiteralPath $patches -File -Filter $pattern|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($null -ne $item){$items += $item.FullName}
}
if(Test-Path -LiteralPath (Get-StatePath) -PathType Leaf){$items += (Get-StatePath)}
$result=Join-Path $patches "SharpEmu_V75_0_1_3_RESULT_$stamp.zip"
Compress-Archive -LiteralPath $items -DestinationPath $result -Force
$summary.GetEnumerator()|ForEach-Object{Write-Host "$($_.Key)=$($_.Value)"}
Write-Tag "SUMMARY=$summaryPath"
Write-Tag "RAD_EVIDENCE=$evidencePath"
Write-Tag "RESULT_ZIP=$result"
