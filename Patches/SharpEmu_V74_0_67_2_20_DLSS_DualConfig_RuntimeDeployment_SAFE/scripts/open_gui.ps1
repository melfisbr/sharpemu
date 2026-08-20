. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$debugRoot=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64'
$debugHost=Join-Path $debugRoot 'SharpEmu.exe'
$provider=Join-Path $debugRoot 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $debugRoot 'nvngx_dlss.dll'

foreach($path in @($debugHost,$provider,$ngx)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "[V74.0.67.2.20] Debug runtime missing: $path"
    }
}

foreach($export in @(
    'sharpemu_vk_upscaler_get_instance_extensions',
    'sharpemu_vk_upscaler_get_device_extensions',
    'sharpemu_vk_upscaler_get_capabilities',
    'sharpemu_vk_upscaler_initialize',
    'sharpemu_vk_upscaler_dispatch',
    'sharpemu_vk_upscaler_shutdown',
    'sharpemu_vk_upscaler_get_last_error'))
{
    if(!(Test-NativeExport -DllPath $provider -ExportName $export)){
        throw "[V74.0.67.2.20] Debug provider export missing: $export"
    }
}

Remove-Item Env:SHARPEMU_VK_UPSCALER -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_QUALITY -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_NATIVE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DLSS_DATA_PATH -ErrorAction SilentlyContinue

Write-Host '[V74.0.67.2.20] DEBUG runtime deployment verified before launch.'
Write-Host "[V74.0.67.2.20] Provider=$provider"
Write-Host "[V74.0.67.2.20] NGX=$ngx"
Write-Host '[V74.0.67.2.20] Opening the same Debug configuration that previously logged exists=0.'
Write-Host '[V74.0.67.2.20] In Rendering keep DLSS enabled + Ultra Performance, then launch Demon''s Souls.'
Write-Host '[V74.0.67.2.20] Expected status after temporal scene begins: ACTIVE / NVIDIA DLSS.'
Write-Host '[V74.0.67.2.20] Expected proof: provider=1 caps=0x9 selected=dlss state=active dlss_dispatches>0.'

$process=Start-Process `
    -FilePath $debugHost `
    -WorkingDirectory $debugRoot `
    -PassThru

$process.WaitForExit()
Write-Host "[V74.0.67.2.20] ProcessExitCode=$($process.ExitCode)"
