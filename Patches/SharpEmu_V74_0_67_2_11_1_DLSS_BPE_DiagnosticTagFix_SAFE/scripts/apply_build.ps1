. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$info=Join-Path $patches 'SharpEmu_V74_0_67_2_10_DLSS_PROVIDER_BUILD.txt'
$provider=$null;$ngxDll=$null;$reuseProvider=$false

if(Test-Path -LiteralPath $info){
    $values=@{}
    foreach($line in Get-Content -LiteralPath $info){
        $parts=$line -split '=',2
        if($parts.Count-eq 2){$values[$parts[0]]=$parts[1]}
    }

    $provider=$values['PROVIDER']
    $ngxDll=$values['NGX_DLL']

    if(![string]::IsNullOrWhiteSpace($provider) -and
       ![string]::IsNullOrWhiteSpace($ngxDll) -and
       (Test-Path -LiteralPath $provider) -and
       (Test-Path -LiteralPath $ngxDll)){
        try{
            $reuseProvider=
                Test-NativeExport `
                    -DllPath $provider `
                    -ExportName 'sharpemu_vk_upscaler_get_last_error'
        }catch{
            $reuseProvider=$false
        }
    }
}

if($reuseProvider){
    Write-Host '[V74.0.67.2.11.1] Reusing successful V2.10 native provider.'
    Write-Host "[V74.0.67.2.11.1] ProviderBuild=$provider"
    Write-Host "[V74.0.67.2.11.1] NGX_DLL=$ngxDll"
}else{
    Write-Host '[V74.0.67.2.11.1] Cached V2.10 provider missing/invalid; rebuilding.'
    & (Join-Path $PSScriptRoot 'bootstrap_provider.ps1')

    if(!(Test-Path -LiteralPath $info)){
        throw 'Provider build info missing after bootstrap.'
    }

    $values=@{}
    foreach($line in Get-Content -LiteralPath $info){
        $parts=$line -split '=',2
        if($parts.Count-eq 2){$values[$parts[0]]=$parts[1]}
    }
    $provider=$values['PROVIDER']
    $ngxDll=$values['NGX_DLL']
}

if(!(Test-Path -LiteralPath $provider)){
    throw "Provider DLL missing: $provider"
}
if(!(Test-Path -LiteralPath $ngxDll)){
    throw "NGX DLL missing: $ngxDll"
}
if(!(Test-NativeExport `
        -DllPath $provider `
        -ExportName 'sharpemu_vk_upscaler_get_last_error')){
    throw 'Provider does not expose sharpemu_vk_upscaler_get_last_error.'
}

$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$text=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$needs=!$text.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')

$backup=$null
if($needs){
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_11_$stamp"
    New-Item -ItemType Directory -Force -Path $backup|Out-Null
    Copy-Item `
        -LiteralPath $bridge `
        -Destination (Join-Path $backup 'VulkanUpscalerBridge.cs') `
        -Force
    Copy-Item `
        -LiteralPath $exceptions `
        -Destination (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') `
        -Force
    try{
        & (Join-Path $PSScriptRoot 'patch_source.ps1')
        & (Join-Path $PSScriptRoot 'patch_bpe_recovery.ps1')
    }catch{
        Write-Warning '[V74.0.67.2.11.1] Managed patch failed; restoring bridge + exceptions.'
        Copy-Item `
            -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') `
            -Destination $bridge `
            -Force
        Copy-Item `
            -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') `
            -Destination $exceptions `
            -Force
        throw
    }
}else{
    Write-Host '[V74.0.67.2.11.1] DLSS managed source already patched.'
    if(!(Normalize-Lf ([IO.File]::ReadAllText($exceptions))).Contains(
        'V74.0.67.2.11 BPE end-sentinel return repair')){
        $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
        $backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_11_$stamp"
        New-Item -ItemType Directory -Force -Path $backup|Out-Null
        Copy-Item `
            -LiteralPath $bridge `
            -Destination (Join-Path $backup 'VulkanUpscalerBridge.cs') `
            -Force
        Copy-Item `
            -LiteralPath $exceptions `
            -Destination (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') `
            -Force
        try{
            & (Join-Path $PSScriptRoot 'patch_bpe_recovery.ps1')
        }catch{
            Copy-Item `
                -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') `
                -Destination $exceptions `
                -Force
            throw
        }
    }else{
        Write-Host '[V74.0.67.2.11.1] BPE end-sentinel return repair already applied.'
    }
}

Stop-SharpEmuForBuild

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_11_BUILD_$stamp.log"
$cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$oldPreference=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    $output=@(& dotnet build $cli -c Release -r win-x64 2>&1)
    $exitCode=$LASTEXITCODE
}finally{
    $ErrorActionPreference=$oldPreference
}

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
    if($null-ne $backup){
        if(Test-Path -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs')){
            Copy-Item `
                -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') `
                -Destination $bridge `
                -Force
        }
        if(Test-Path -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs')){
            Copy-Item `
                -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') `
                -Destination $exceptions `
                -Force
        }
    }
    throw "SharpEmu.CLI build failed: native exit $exitCode"
}

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){
    throw 'Release win-x64 SharpEmu.exe not found.'
}

$upDir=Join-Path $releaseHost.DirectoryName 'upscalers'
New-Item -ItemType Directory -Force -Path $upDir|Out-Null
$deployedProvider=Join-Path $upDir 'SharpEmu.VulkanUpscaler.Native.dll'
$deployedNgx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'

Copy-Item -LiteralPath $provider -Destination $deployedProvider -Force
Copy-Item -LiteralPath $ngxDll -Destination $deployedNgx -Force

Write-Host '[V74.0.67.2.11.1] APPLY + HOST BUILD + PROVIDER REDEPLOY PASSED.'
Write-Host "[V74.0.67.2.11.1] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.11.1] Provider=$deployedProvider"
Write-Host "[V74.0.67.2.11.1] NGX=$deployedNgx"
Write-Host "[V74.0.67.2.11.1] BuildLog=$buildLog"
if($null-ne $backup){
    Write-Host "[V74.0.67.2.11.1] Backup=$backup"
}
