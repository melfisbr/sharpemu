. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

Remove-Item Env:SHARPEMU_VK_UPSCALER -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_QUALITY -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_NATIVE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DLSS_DATA_PATH -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_DETILE_POOL_MB -ErrorAction SilentlyContinue

Write-Host '[V74.0.67.2.15.1] Opening GUI WITHOUT forced DLSS shell variables.'
Write-Host '[V74.0.67.2.15.1] In Rendering: enable Upscaler, select DLSS, choose Quality (or desired preset), then launch the game.'
Write-Host '[V74.0.67.2.15.1] The frontend now sets backend, quality, pre-composite, RAM cache=2, RAM TTL=120000 and detile pool=64.'
Write-Host '[V74.0.67.2.15.1] Provider path is auto-discovered from the host upscalers directory.'
Write-Host '[V74.0.67.2.15.1] DLSS proof: selected=dlss state=active dlss_dispatches>0.'
Write-Host '[V74.0.67.2.15.1] RAM proof: ttl_ms=120000.'
Write-Host "[V74.0.67.2.15.1] Host=$($releaseHost.FullName)"

Start-Process -FilePath $releaseHost.FullName -WorkingDirectory $releaseHost.DirectoryName
