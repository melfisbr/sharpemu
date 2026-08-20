. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
$csproj=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_20_$stamp"
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item -LiteralPath $csproj -Destination (Join-Path $backup 'SharpEmu.CLI.csproj') -Force

try{
    & (Join-Path $PSScriptRoot 'patch_dualconfig_deployment.ps1')
}catch{
    Copy-Item -LiteralPath (Join-Path $backup 'SharpEmu.CLI.csproj') -Destination $csproj -Force
    throw
}

Stop-SharpEmuForBuild

function Build-ConfigV74067220 {
    param(
        [Parameter(Mandatory=$true)][string]$Configuration,
        [Parameter(Mandatory=$true)][string]$LogPath
    )

    $oldPreference=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        $captured=@(& dotnet build $csproj -c $Configuration -r win-x64 2>&1)
        $exitCode=$LASTEXITCODE
    }finally{
        $ErrorActionPreference=$oldPreference
    }

    $lines=@(
        foreach($item in $captured){
            if($null-eq $item){continue}
            $line=$item.ToString()
            Write-Host $line
            $line
        }
    )
    $lines|Set-Content -LiteralPath $LogPath -Encoding UTF8

    if($exitCode-ne 0){
        throw "$Configuration build failed: native exit $exitCode"
    }
}

$releaseLog=Join-Path $patches "SharpEmu_V74_0_67_2_20_RELEASE_BUILD_$stamp.log"
$debugLog=Join-Path $patches "SharpEmu_V74_0_67_2_20_DEBUG_BUILD_$stamp.log"

try{
    Build-ConfigV74067220 -Configuration 'Release' -LogPath $releaseLog
    Build-ConfigV74067220 -Configuration 'Debug' -LogPath $debugLog
}catch{
    Copy-Item -LiteralPath (Join-Path $backup 'SharpEmu.CLI.csproj') -Destination $csproj -Force
    throw
}

$runtimeRoot=Join-Path $repo 'runtime\dlss'
$canonicalProvider=Join-Path $runtimeRoot 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$canonicalNgx=Join-Path $runtimeRoot 'nvngx_dlss.dll'

$canonicalProviderHash=(Get-FileHash -LiteralPath $canonicalProvider -Algorithm SHA256).Hash
$canonicalNgxHash=(Get-FileHash -LiteralPath $canonicalNgx -Algorithm SHA256).Hash

foreach($config in @('Release','Debug')){
    $configHost=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\SharpEmu.exe"
    $provider=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll"
    $ngx=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\nvngx_dlss.dll"

    foreach($path in @($configHost,$provider,$ngx)){
        if(!(Test-Path -LiteralPath $path -PathType Leaf)){
            throw "[V74.0.67.2.20] $config deployment missing: $path"
        }
    }

    $providerHash=(Get-FileHash -LiteralPath $provider -Algorithm SHA256).Hash
    $ngxHash=(Get-FileHash -LiteralPath $ngx -Algorithm SHA256).Hash

    if($providerHash-ne $canonicalProviderHash){
        throw "[V74.0.67.2.20] $config provider hash differs from canonical runtime."
    }
    if($ngxHash-ne $canonicalNgxHash){
        throw "[V74.0.67.2.20] $config nvngx hash differs from canonical runtime."
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
            throw "[V74.0.67.2.20] $config provider export missing: $export"
        }
    }

    Write-Host "[V74.0.67.2.20] config=$config host=1 provider=1 ngx=1 provider_hash_match=1 ngx_hash_match=1 exports=7/7"
}

Write-Host '[V74.0.67.2.20] APPLY + DEBUG/RELEASE BUILD + DUAL DEPLOYMENT PASSED.'
Write-Host "[V74.0.67.2.20] ReleaseBuildLog=$releaseLog"
Write-Host "[V74.0.67.2.20] DebugBuildLog=$debugLog"
Write-Host "[V74.0.67.2.20] Backup=$backup"
