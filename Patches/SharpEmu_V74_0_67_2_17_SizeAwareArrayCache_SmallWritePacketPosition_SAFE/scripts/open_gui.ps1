. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

# Preserve the frontend-only DLSS proof.
Remove-Item Env:SHARPEMU_VK_UPSCALER -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_QUALITY -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_NATIVE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DLSS_DATA_PATH -ErrorAction SilentlyContinue

# V2.17 behavior is source-default ON. Clear A/B overrides so the test uses it.
Remove-Item Env:SHARPEMU_LARGE_ARRAY_SIZE_AWARE_ADMISSION -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_SMALL_WRITE_DATA_PACKET_POSITION -ErrorAction SilentlyContinue

Write-Host '[V74.0.67.2.17] Opening GUI without forced DLSS shell variables.'
Write-Host '[V74.0.67.2.17] Rendering: enable Upscaler, select DLSS, choose preset, launch the game.'
Write-Host '[V74.0.67.2.17] Expected RAM markers: ARRAY_CACHE_ADMISSION bypass-smaller/replace-smaller.'
Write-Host '[V74.0.67.2.17] Expected wait marker: SMALL_WRITE_PACKET_POSITION.'
Write-Host '[V74.0.67.2.17] If any SLOW_WAIT_PRODUCER remains, compare producer_complete_ms vs post_complete_wait_ms.'
Write-Host '[V74.0.67.2.17] DLSS proof remains selected=dlss state=active dlss_dispatches>0.'
Write-Host "[V74.0.67.2.17] Host=$($releaseHost.FullName)"

$process=Start-Process `
    -FilePath $releaseHost.FullName `
    -WorkingDirectory $releaseHost.DirectoryName `
    -PassThru

$process.WaitForExit()
Write-Host "[V74.0.67.2.17] ProcessExitCode=$($process.ExitCode)"
