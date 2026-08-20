. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

# Frontend-only proof: clear validation-shell overrides.
Remove-Item Env:SHARPEMU_VK_UPSCALER -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_QUALITY -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_PRECOMPOSITE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_UPSCALER_NATIVE -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_DLSS_DATA_PATH -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS -ErrorAction SilentlyContinue
Remove-Item Env:SHARPEMU_VK_DETILE_POOL_MB -ErrorAction SilentlyContinue

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V74_0_67_2_16_1_RUNTIME_STDOUT_$stamp.log"
$stderr=Join-Path $patches "SharpEmu_V74_0_67_2_16_1_RUNTIME_STDERR_$stamp.log"
$analysis=Join-Path $patches "SharpEmu_V74_0_67_2_16_1_RUNTIME_ANALYSIS_$stamp.txt"
$sourceAudit=Join-Path $patches "SharpEmu_V74_0_67_2_16_1_SOURCE_AUDIT_RUNTIME_$stamp.txt"

Write-Host '[V74.0.67.2.16.1] Opening GUI with NO forced DLSS shell variables.'
Write-Host '[V74.0.67.2.16.1] Rendering: enable Upscaler, select DLSS, choose desired preset, then launch.'
Write-Host '[V74.0.67.2.16.1] Close SharpEmu normally when the test is complete; this script then analyzes RAM/waits automatically.'
Write-Host "[V74.0.67.2.16.1] Host=$($releaseHost.FullName)"

& (Join-Path $PSScriptRoot 'source_audit.ps1') -OutputPath $sourceAudit

$process=Start-Process `
    -FilePath $releaseHost.FullName `
    -WorkingDirectory $releaseHost.DirectoryName `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$process.WaitForExit()
$exitCode=$process.ExitCode
Write-Host "[V74.0.67.2.16.1] ProcessExitCode=$exitCode"

& (Join-Path $PSScriptRoot 'analyze_runtime.ps1') `
    -LogPaths @($stdout,$stderr) `
    -OutputPath $analysis

$zip=Join-Path $patches "SharpEmu_V74_0_67_2_16_1_RUNTIME_AUDIT_$stamp.zip"
$items=@($stdout,$stderr,$analysis,$sourceAudit) |
    Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}

Compress-Archive -LiteralPath $items -DestinationPath $zip -Force

Write-Host "[V74.0.67.2.16.1] RuntimeAuditZip=$zip"
Write-Host '[V74.0.67.2.16.1] Send the RUNTIME_AUDIT ZIP/result; it contains the exact source windows needed for the next behavioral correction.'
