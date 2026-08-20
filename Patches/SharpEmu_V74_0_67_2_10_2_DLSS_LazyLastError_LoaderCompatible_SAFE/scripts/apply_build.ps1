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
    Write-Host '[V74.0.67.2.10.2] Reusing successful V2.10 native provider.'
    Write-Host "[V74.0.67.2.10.2] ProviderBuild=$provider"
    Write-Host "[V74.0.67.2.10.2] NGX_DLL=$ngxDll"
}else{
    Write-Host '[V74.0.67.2.10.2] Cached V2.10 provider missing/invalid; rebuilding.'
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
$text=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$needs=!$text.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')

$backup=$null
if($needs){
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_10_2_$stamp"
    New-Item -ItemType Directory -Force -Path $backup|Out-Null
    Copy-Item `
        -LiteralPath $bridge `
        -Destination (Join-Path $backup 'VulkanUpscalerBridge.cs') `
        -Force
    try{
        & (Join-Path $PSScriptRoot 'patch_source.ps1')
    }catch{
        Write-Warning '[V74.0.67.2.10.2] Managed patch failed; restoring bridge.'
        Copy-Item `
            -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') `
            -Destination $bridge `
            -Force
        throw
    }
}else{
    Write-Host '[V74.0.67.2.10.2] Managed source already patched.'
}

Stop-SharpEmuForBuild

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_10_2_BUILD_$stamp.log"
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
    if($needs -and $null-ne $backup){
        Copy-Item `
            -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') `
            -Destination $bridge `
            -Force
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

Write-Host '[V74.0.67.2.10.2] APPLY + HOST BUILD + PROVIDER REDEPLOY PASSED.'
Write-Host "[V74.0.67.2.10.2] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.10.2] Provider=$deployedProvider"
Write-Host "[V74.0.67.2.10.2] NGX=$deployedNgx"
Write-Host "[V74.0.67.2.10.2] BuildLog=$buildLog"
if($null-ne $backup){
    Write-Host "[V74.0.67.2.10.2] Backup=$backup"
}
