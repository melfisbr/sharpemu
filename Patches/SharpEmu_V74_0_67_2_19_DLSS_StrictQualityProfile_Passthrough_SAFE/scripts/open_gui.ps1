. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

# Prove the Rendering UI owns both backend and quality.
Remove-Item Env:SHARPEMU_VK_UPSCALER -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_QUALITY -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_NATIVE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DLSS_DATA_PATH -ErrorAction SilentlyContinue

Write-Host '[V74.0.67.2.19] Opening GUI without forced backend/profile variables.'
Write-Host '[V74.0.67.2.19] Rendering: enable Upscaler, select DLSS, then select the profile you want.'
Write-Host '[V74.0.67.2.19] The selected profile must now remain identical through frontend -> managed bridge -> native NGX.'
Write-Host '[V74.0.67.2.19] Expected UltraPerformance proof: requested_quality=ultraperformance effective_quality=ultraperformance quality=ultraperformance.'
Write-Host '[V74.0.67.2.19] Quality/Balanced/Performance must likewise report the same requested/effective value.'
Write-Host "[V74.0.67.2.19] Host=$($releaseHost.FullName)"

$process=Start-Process `
    -FilePath $releaseHost.FullName `
    -WorkingDirectory $releaseHost.DirectoryName `
    -PassThru

$process.WaitForExit()
Write-Host "[V74.0.67.2.19] ProcessExitCode=$($process.ExitCode)"
