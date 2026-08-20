. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

Write-Host '[V74.0.67.2.13.2] No runtime source change required.'
Write-Host '[V74.0.67.2.13.2] V2.13.1 already built/applied DLSS activation + RAM content identity.'
Write-Host '[V74.0.67.2.13.2] This package corrects diagnostic ownership only.'

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'

if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

foreach($export in @(
    'sharpemu_vk_upscaler_initialize',
    'sharpemu_vk_upscaler_dispatch',
    'sharpemu_vk_upscaler_get_last_error'
)){
    if(!(Test-NativeExport -DllPath $provider -ExportName $export)){
        throw "Provider export missing: $export"
    }
}

Write-Host '[V74.0.67.2.13.2] APPLY/BUILD CHECK PASSED (no rebuild necessary).'
Write-Host "[V74.0.67.2.13.2] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.13.2] Provider=$provider"
Write-Host "[V74.0.67.2.13.2] NGX=$ngx"
