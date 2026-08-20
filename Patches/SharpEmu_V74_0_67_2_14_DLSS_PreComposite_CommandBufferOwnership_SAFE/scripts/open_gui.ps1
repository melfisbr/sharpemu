. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

$ngxData=Join-Path $patches 'NGXRuntime'
New-Item -ItemType Directory -Force -Path $ngxData|Out-Null

$env:SHARPEMU_VK_UPSCALER='dlss'
$env:SHARPEMU_VK_UPSCALER_QUALITY='quality'
$env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE='1'
$env:SHARPEMU_VK_UPSCALER_NATIVE=$provider
$env:SHARPEMU_DLSS_DATA_PATH=$ngxData

$env:SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES='2'
$env:SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS='120000'
$env:SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS='120000'
$env:SHARPEMU_VK_DETILE_POOL_MB='64'

Write-Host '[V74.0.67.2.14] Opening accumulated SharpEmu Release host.'
Write-Host '[V74.0.67.2.14] DLSS forced: backend=dlss quality=quality precomposite=1.'
Write-Host '[V74.0.67.2.14] Expected: COMMAND_BUFFER state=recording -> create_dlss_feature -> evaluate_dlss.'
Write-Host '[V74.0.67.2.14] RAM: cache=2; array+texture reuse both 120000ms; detile pool=64MiB.'
Write-Host '[V74.0.67.2.14] DLSS truth: selected=dlss state=active dlss_dispatches>0.'
Write-Host "[V74.0.67.2.14] NGXData=$ngxData"
Write-Host "[V74.0.67.2.14] Host=$($releaseHost.FullName)"
Start-Process -FilePath $releaseHost.FullName -WorkingDirectory $releaseHost.DirectoryName
