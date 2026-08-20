. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

# No shell-forced DLSS. Rendering remains the owner.
Remove-Item Env:SHARPEMU_VK_UPSCALER -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_QUALITY -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_NATIVE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DLSS_DATA_PATH -ErrorAction SilentlyContinue

# Ensure the new recovery uses its source default ON.
Remove-Item Env:SHARPEMU_DISABLE_DEMON_BPE_HEAD2_SENTINEL_RECOVERY -ErrorAction SilentlyContinue

Write-Host '[V74.0.67.2.18] Opening GUI. DLSS is still controlled only by Rendering.'
Write-Host '[V74.0.67.2.18] Expected crash-recovery marker if the exact head2 case recurs:'
Write-Host '[V74.0.67.2.18]   [V74.0.67.2.18][BPE_HEAD2_SENTINEL_RECOVERY]'
Write-Host '[V74.0.67.2.18] Recovery is gated to target=0xA, RCX=RAX=2, BPE primary-r14, exact caller and caller-end payload.'
Write-Host "[V74.0.67.2.18] Host=$($releaseHost.FullName)"

$process=Start-Process `
    -FilePath $releaseHost.FullName `
    -WorkingDirectory $releaseHost.DirectoryName `
    -PassThru

$process.WaitForExit()
Write-Host "[V74.0.67.2.18] ProcessExitCode=$($process.ExitCode)"
