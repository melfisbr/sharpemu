. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$csproj=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_21_$stamp"
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item -LiteralPath $exceptions -Destination (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Force

try{
    & (Join-Path $PSScriptRoot 'patch_highgraphics_pthread_exit.ps1')
}catch{
    Copy-Item -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Destination $exceptions -Force
    throw
}

Stop-SharpEmuForBuild

function Build-ConfigV74067221 {
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

$debugLog=Join-Path $patches "SharpEmu_V74_0_67_2_21_DEBUG_BUILD_$stamp.log"
$releaseLog=Join-Path $patches "SharpEmu_V74_0_67_2_21_RELEASE_BUILD_$stamp.log"

try{
    Build-ConfigV74067221 -Configuration 'Debug' -LogPath $debugLog
    Build-ConfigV74067221 -Configuration 'Release' -LogPath $releaseLog
}catch{
    Copy-Item -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Destination $exceptions -Force
    throw
}

# V2.20 deployment must still be valid in both configurations.
$runtimeProvider=Join-Path $repo 'runtime\dlss\upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$runtimeNgx=Join-Path $repo 'runtime\dlss\nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $runtimeProvider -PathType Leaf)){throw 'Canonical provider missing.'}
if(!(Test-Path -LiteralPath $runtimeNgx -PathType Leaf)){throw 'Canonical nvngx_dlss.dll missing.'}

$providerHash=(Get-FileHash -LiteralPath $runtimeProvider -Algorithm SHA256).Hash
$ngxHash=(Get-FileHash -LiteralPath $runtimeNgx -Algorithm SHA256).Hash

foreach($config in @('Debug','Release')){
    $configHost=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\SharpEmu.exe"
    $provider=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll"
    $ngx=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\nvngx_dlss.dll"

    foreach($path in @($configHost,$provider,$ngx)){
        if(!(Test-Path -LiteralPath $path -PathType Leaf)){
            throw "[V74.0.67.2.21] $config runtime missing: $path"
        }
    }

    if((Get-FileHash -LiteralPath $provider -Algorithm SHA256).Hash-ne $providerHash){
        throw "[V74.0.67.2.21] $config provider hash mismatch."
    }
    if((Get-FileHash -LiteralPath $ngx -Algorithm SHA256).Hash-ne $ngxHash){
        throw "[V74.0.67.2.21] $config NGX hash mismatch."
    }
}

Write-Host '[V74.0.67.2.21] APPLY + DEBUG/RELEASE BUILD PASSED.'
Write-Host '[V74.0.67.2.21] V2.20 DLSS dual-config deployment preserved.'
Write-Host "[V74.0.67.2.21] DebugBuildLog=$debugLog"
Write-Host "[V74.0.67.2.21] ReleaseBuildLog=$releaseLog"
Write-Host "[V74.0.67.2.21] Backup=$backup"
