. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$current=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$needs=!$current.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')

$backup=$null
if($needs){
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_14_$stamp"
    New-Item -ItemType Directory -Force -Path $backup|Out-Null
    Copy-Item -LiteralPath $bridge -Destination (Join-Path $backup 'VulkanUpscalerBridge.cs') -Force
    try{
        & (Join-Path $PSScriptRoot 'patch_precomposite_command_buffer.ps1')
    }catch{
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') -Destination $bridge -Force
        throw
    }
}else{
    Write-Host '[V74.0.67.2.14] Source already patched.'
}

Stop-SharpEmuForBuild

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_14_DLSS_COMMAND_BUFFER_BUILD_$stamp.log"
$cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$oldPreference=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    $output=@(& dotnet build $cli -c Release -r win-x64 2>&1)
    $exitCode=$LASTEXITCODE
}finally{$ErrorActionPreference=$oldPreference}

$lines=@(
    foreach($item in $output){
        if($null-eq $item){continue}
        $line=$item.ToString()
        Write-Host $line
        $line
    }
)
$lines|Set-Content -LiteralPath $buildLog -Encoding UTF8

if($exitCode-ne 0){
    if($needs -and $null-ne $backup){
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') -Destination $bridge -Force
    }
    throw "SharpEmu.CLI build failed: native exit $exitCode"
}

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

Write-Host '[V74.0.67.2.14] APPLY + RELEASE BUILD PASSED.'
Write-Host '[V74.0.67.2.14] Native provider unchanged and revalidated.'
Write-Host "[V74.0.67.2.14] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.14] BuildLog=$buildLog"
if($null-ne $backup){Write-Host "[V74.0.67.2.14] Backup=$backup"}
