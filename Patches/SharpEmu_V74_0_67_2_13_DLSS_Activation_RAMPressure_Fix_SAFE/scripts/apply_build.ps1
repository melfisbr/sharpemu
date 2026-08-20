. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

& (Join-Path $PSScriptRoot 'bootstrap_provider.ps1')
$info=Join-Path $patches 'SharpEmu_V74_0_67_2_13_DLSS_PROVIDER_BUILD.txt'
if(!(Test-Path -LiteralPath $info)){throw 'V2.13 provider build info missing.'}
$values=@{}
foreach($line in Get-Content -LiteralPath $info){
    $parts=$line -split '=',2
    if($parts.Count-eq 2){$values[$parts[0]]=$parts[1]}
}
$provider=$values['PROVIDER'];$ngxDll=$values['NGX_DLL']
if(!(Test-Path -LiteralPath $provider)){throw "Provider DLL missing: $provider"}
if(!(Test-Path -LiteralPath $ngxDll)){throw "NGX DLL missing: $ngxDll"}

$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$agc=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_13_$stamp"
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item $bridge (Join-Path $backup 'VulkanUpscalerBridge.cs') -Force
Copy-Item $agc (Join-Path $backup 'AgcExports.cs') -Force
Copy-Item $exceptions (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Force

try{
    $et=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
    if(!$et.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')){
        & (Join-Path $PSScriptRoot 'patch_bpe_secondary_caller.ps1')
    }
    & (Join-Path $PSScriptRoot 'patch_dlss_activation.ps1')
    & (Join-Path $PSScriptRoot 'patch_ram_pressure.ps1')
}catch{
    Copy-Item (Join-Path $backup 'VulkanUpscalerBridge.cs') $bridge -Force
    Copy-Item (Join-Path $backup 'AgcExports.cs') $agc -Force
    Copy-Item (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') $exceptions -Force
    throw
}

Stop-SharpEmuForBuild
$buildStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_13_DLSS_RAM_BUILD_$buildStamp.log"
$cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
$oldPreference=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    $output=@(& dotnet build $cli -c Release -r win-x64 2>&1)
    $exitCode=$LASTEXITCODE
}finally{$ErrorActionPreference=$oldPreference}
$lines=@(foreach($item in $output){if($null-ne $item){$line=$item.ToString();Write-Host $line;$line}})
$lines|Set-Content $buildLog -Encoding UTF8
if($exitCode-ne 0){
    Copy-Item (Join-Path $backup 'VulkanUpscalerBridge.cs') $bridge -Force
    Copy-Item (Join-Path $backup 'AgcExports.cs') $agc -Force
    Copy-Item (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') $exceptions -Force
    throw "SharpEmu.CLI build failed: native exit $exitCode"
}

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}
$upDir=Join-Path $releaseHost.DirectoryName 'upscalers'
New-Item -ItemType Directory -Force -Path $upDir|Out-Null
$deployedProvider=Join-Path $upDir 'SharpEmu.VulkanUpscaler.Native.dll'
$deployedNgx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
Copy-Item $provider $deployedProvider -Force
Copy-Item $ngxDll $deployedNgx -Force

Write-Host '[V74.0.67.2.13] APPLY + RELEASE BUILD + V2.13 PROVIDER DEPLOY PASSED.'
Write-Host "[V74.0.67.2.13] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.13] Provider=$deployedProvider"
Write-Host "[V74.0.67.2.13] NGX=$deployedNgx"
Write-Host "[V74.0.67.2.13] BuildLog=$buildLog"
Write-Host "[V74.0.67.2.13] Backup=$backup"
