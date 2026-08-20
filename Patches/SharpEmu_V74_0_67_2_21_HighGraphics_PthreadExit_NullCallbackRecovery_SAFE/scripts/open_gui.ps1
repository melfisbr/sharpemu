. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$debugRoot=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64'
$debugHost=Join-Path $debugRoot 'SharpEmu.exe'
$provider=Join-Path $debugRoot 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $debugRoot 'nvngx_dlss.dll'

foreach($path in @($debugHost,$provider,$ngx)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "[V74.0.67.2.21] Debug runtime missing: $path"
    }
}

Remove-Item Env:SHARPEMU_VK_UPSCALER -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_QUALITY -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_NATIVE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DLSS_DATA_PATH -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DISABLE_HIGHGRAPHICS_PTHREAD_EXIT_NULL_RECOVERY -ErrorAction SilentlyContinue

Write-Host '[V74.0.67.2.21] Opening Debug runtime.'
Write-Host '[V74.0.67.2.21] V2.20 DLSS provider deployment is preserved.'
Write-Host '[V74.0.67.2.21] Keep DLSS enabled through Rendering; no shell override is used.'
Write-Host '[V74.0.67.2.21] If the boot cleanup reproduces the proven case, expect:'
Write-Host '[V74.0.67.2.21]   [V74.0.67.2.21][PTHREAD_EXIT_NULL_CALLBACK]'
Write-Host '[V74.0.67.2.21] followed by continued boot instead of process exit -1073741819.'

$process=Start-Process `
    -FilePath $debugHost `
    -WorkingDirectory $debugRoot `
    -PassThru

$process.WaitForExit()
Write-Host "[V74.0.67.2.21] ProcessExitCode=$($process.ExitCode)"
