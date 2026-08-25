param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$current=Get-CurrentSourceState
Write-CurrentState $current

$backup=Find-PreV75Backup
Assert-PreV75Backup $backup

$rad=Get-InstalledRadVideo64
if($null -eq $rad){
    throw "$script:Tag official RAD executable not found"
}

$adapterPaths=@(Get-NativeAdapterPaths)
$adapterPresent=@($adapterPaths|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}).Count

Write-Tag "NativeAdapterPresentCount=$adapterPresent"
Write-Tag "ExternalRAD=$rad"

$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$report=Join-Path $patches "SharpEmu_V75_0_1_2_RAD_RESTORE_PRECHECK_$stamp.txt"

@(
    "version=$script:Version",
    "current_host_sha=$($current.HostSha)",
    "current_playback_sha=$($current.PlaybackSha)",
    "current_native_host_marker=$($current.NativeHostMarker)",
    "current_native_playback_marker=$($current.NativePlaybackMarker)",
    "current_native_abi_exists=$($current.NativeAbiExists)",
    "current_native_decoder_exists=$($current.NativeDecoderExists)",
    "native_adapter_present_count=$adapterPresent",
    "pre_v75_backup=$($backup.FullName)",
    "pre_v75_host_sha=$(Get-Sha (Join-Path $backup.FullName 'HostMovieBridge.cs'))",
    "pre_v75_playback_sha=$(Get-Sha (Join-Path $backup.FullName 'MediaFramePlayback.cs'))",
    "radvideo64=$rad",
    'restore_policy=exact-clean-pre-V75-backup',
    'native_adapter_policy=remove-debug-and-release',
    'source_write=0'
)|Set-Content -LiteralPath $report -Encoding UTF8

Write-Tag "PRECHECK=$report"
Write-Tag 'PRECHECK PASSED. Nothing changed.'
