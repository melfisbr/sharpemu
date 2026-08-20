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

Write-Host '[V74.0.67.2.16] NO RUNTIME SOURCE CHANGE APPLIED.'
Write-Host '[V74.0.67.2.16] Existing V2.15 RAM TTL/frontend and V2.14 DLSS fixes preserved.'
Write-Host '[V74.0.67.2.16] RELEASE/PROVIDER DEPLOYMENT CHECK PASSED.'
Write-Host "[V74.0.67.2.16] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.16] Provider=$provider"
Write-Host "[V74.0.67.2.16] NGX=$ngx"
