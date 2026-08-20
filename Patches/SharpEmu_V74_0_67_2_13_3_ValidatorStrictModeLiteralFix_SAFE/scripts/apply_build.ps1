. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}
$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider -PathType Leaf)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx -PathType Leaf)){throw "nvngx_dlss.dll missing: $ngx"}

foreach($export in @(
    'sharpemu_vk_upscaler_get_instance_extensions',
    'sharpemu_vk_upscaler_get_device_extensions',
    'sharpemu_vk_upscaler_get_capabilities',
    'sharpemu_vk_upscaler_initialize',
    'sharpemu_vk_upscaler_dispatch',
    'sharpemu_vk_upscaler_shutdown',
    'sharpemu_vk_upscaler_get_last_error')){
    if(!(Test-NativeExport -DllPath $provider -ExportName $export)){
        throw "Provider export missing: $export"
    }
}

Write-Host '[V74.0.67.2.13.3] NO RUNTIME SOURCE CHANGE REQUIRED.'
Write-Host '[V74.0.67.2.13.3] V2.13.1 runtime build/provider/RAM patch already applied.'
Write-Host '[V74.0.67.2.13.3] APPLY/BUILD DEPLOYMENT CHECK PASSED.'
Write-Host "[V74.0.67.2.13.3] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.13.3] Provider=$provider"
Write-Host "[V74.0.67.2.13.3] NGX=$ngx"
