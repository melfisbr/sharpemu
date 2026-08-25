param()
. (Join-Path $PSScriptRoot 'common.ps1')

$patches=Get-PatchesRoot
$latest=Get-ChildItem -LiteralPath $patches -File -Filter 'SharpEmu_V75_0_1_1_BINK2_RUNTIME_*.log' |
    Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -eq $latest){
    throw "$script:Tag no V75.0.1.1 runtime log found"
}

$state=Read-RuntimeState
$runtimeFound=
    $null -ne $state -and
    $state.PSObject.Properties.Name -contains 'runtime_found' -and
    [bool]$state.runtime_found

$lines=@(Get-Content -LiteralPath $latest.FullName)
function Count-Simple([string]$Text){
    @($lines|Select-String -SimpleMatch $Text).Count
}
function Count-Movie([string]$Movie,[string]$Marker){
    @($lines|Where-Object{
        $_ -like "*$Movie*" -and
        $_ -like "*$Marker*"
    }).Count
}

$summary=[ordered]@{
    version='V75.0.1.1'
    runtime_log=$latest.FullName
    runtime_found=$runtimeFound
    runtime_mode=$(if($null -ne $state){$state.runtime_mode}else{'unknown'})
    adapter_loaded_count=(Count-Simple '[BINK-NATIVE][V75.0.0] adapter_loaded')
    auto_selected_count=(Count-Simple '[BINK-NATIVE][V75.0.0] auto_selected')
    native_open_ok_count=(Count-Simple '[BINK-NATIVE][V75.0.0] open_ok')
    native_bridge_attached_count=(Count-Simple '[BINK-NATIVE][V75.0.0] bridge_attached')
    native_runtime_missing_count=(Count-Simple 'compatible-x64-bink2-runtime-not-found')
    logo_loop_native_count=(Count-Movie 'logo_intro_loop.bk2' 'decoder=in-process-sdk')
    main_menu_native_count=(Count-Movie 'main_menu.bk2' 'decoder=in-process-sdk')
    logo_loop_external_count=(Count-Movie 'logo_intro_loop.bk2' 'Bink RAD bridge attached')
    main_menu_external_count=(Count-Movie 'main_menu.bk2' 'Bink RAD bridge attached')
    main_menu_capture_import_count=(Count-Simple 'RAD_MAIN_MENU_CAPTURE_IMPORT')
    texture_injection_count=(Count-Simple 'RAD_UI_TEXTURE_BIND')
    device_lost_count=((Count-Simple 'ErrorDeviceLost')+(Count-Simple 'Vulkan device lost'))
    native_decode_error_count=((Count-Simple 'Native Bink decode failed')+(Count-Simple 'BinkCopyToBuffer-failed'))
}

$summary['classification']=
    if($summary.device_lost_count -gt 0){'device-lost'}
    elseif($runtimeFound -and $summary.native_decode_error_count -gt 0){'native-runtime-decode-error'}
    elseif($runtimeFound -and $summary.logo_loop_native_count -eq 0){'runtime-present-logo-loop-not-native'}
    elseif($runtimeFound -and $summary.main_menu_native_count -eq 0){'runtime-present-main-menu-not-native'}
    elseif($runtimeFound -and ($summary.logo_loop_external_count -gt 0 -or $summary.main_menu_external_count -gt 0)){'runtime-present-ui-bink-fell-back-external'}
    elseif($runtimeFound){'ui-binks-in-process-native-rad-visual-verification-required'}
    elseif($summary.logo_loop_external_count -gt 0 -or $summary.main_menu_external_count -gt 0){'native-runtime-unavailable-external-rad-fallback-active'}
    else{'native-runtime-unavailable-no-rad-route-observed'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryPath=Join-Path $patches "SharpEmu_V75_0_1_1_SUMMARY_$stamp.txt"
$evidencePath=Join-Path $patches "SharpEmu_V75_0_1_1_NATIVE_EVIDENCE_$stamp.txt"
$summary.GetEnumerator()|ForEach-Object{
    "$($_.Key)=$($_.Value)"
}|Set-Content -LiteralPath $summaryPath -Encoding UTF8

$lines|Where-Object{
    $_ -like '*BINK-NATIVE*' -or
    $_ -like '*logo_intro_loop.bk2*' -or
    $_ -like '*main_menu.bk2*' -or
    $_ -like '*compatible-x64-bink2-runtime-not-found*' -or
    $_ -like '*RAD_MAIN_MENU_CAPTURE_IMPORT*' -or
    $_ -like '*RAD_UI_TEXTURE_BIND*'
}|Set-Content -LiteralPath $evidencePath -Encoding UTF8

$items=@($latest.FullName,$summaryPath,$evidencePath)
if(Test-Path -LiteralPath (Get-StatePath)){
    $items += (Get-StatePath)
}
$resultZip=Join-Path $patches "SharpEmu_V75_0_1_1_RESULT_$stamp.zip"
Compress-Archive -LiteralPath $items -DestinationPath $resultZip -Force

$summary.GetEnumerator()|ForEach-Object{
    Write-Host "$($_.Key)=$($_.Value)"
}
Write-Tag "SUMMARY=$summaryPath"
Write-Tag "NATIVE_EVIDENCE=$evidencePath"
Write-Tag "RESULT_ZIP=$resultZip"
