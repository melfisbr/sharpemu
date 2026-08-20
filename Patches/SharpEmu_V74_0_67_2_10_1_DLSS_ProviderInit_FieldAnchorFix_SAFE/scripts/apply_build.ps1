. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

# Reuse the V2.10 provider that already built successfully when valid.
$info=Join-Path $patches 'SharpEmu_V74_0_67_2_10_DLSS_PROVIDER_BUILD.txt'
$provider=$null;$ngxDll=$null;$reuseProvider=$false

if(Test-Path -LiteralPath $info){
    $values=@{}
    foreach($line in Get-Content -LiteralPath $info){
        $parts=$line -split '=',2
        if($parts.Count-eq 2){$values[$parts[0]]=$parts[1]}
    }
    $provider=$values['PROVIDER'];$ngxDll=$values['NGX_DLL']
    if(![string]::IsNullOrWhiteSpace($provider) -and
       ![string]::IsNullOrWhiteSpace($ngxDll) -and
       (Test-Path -LiteralPath $provider) -and
       (Test-Path -LiteralPath $ngxDll)){
        try{
            $reuseProvider=
                Test-NativeExport -DllPath $provider `
                    -ExportName 'sharpemu_vk_upscaler_get_last_error'
        }catch{$reuseProvider=$false}
    }
}

if($reuseProvider){
    Write-Host '[V74.0.67.2.10.1] Reusing successfully built V2.10 provider.'
    Write-Host "[V74.0.67.2.10.1] ProviderBuild=$provider"
    Write-Host "[V74.0.67.2.10.1] NGX_DLL=$ngxDll"
}else{
    Write-Host '[V74.0.67.2.10.1] Cached provider invalid/missing; rebuilding.'
    & (Join-Path $PSScriptRoot 'bootstrap_provider.ps1')
    if(!(Test-Path -LiteralPath $info)){throw 'Provider build info missing.'}
    $values=@{}
    foreach($line in Get-Content -LiteralPath $info){
        $parts=$line -split '=',2
        if($parts.Count-eq 2){$values[$parts[0]]=$parts[1]}
    }
    $provider=$values['PROVIDER'];$ngxDll=$values['NGX_DLL']
}

if(!(Test-Path -LiteralPath $provider)){throw "Provider DLL missing: $provider"}
if(!(Test-Path -LiteralPath $ngxDll)){throw "NGX DLL missing: $ngxDll"}
if(!(Test-NativeExport -DllPath $provider -ExportName 'sharpemu_vk_upscaler_get_last_error')){
    throw 'Provider does not expose sharpemu_vk_upscaler_get_last_error.'
}

$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$text=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$needs=!$text.Contains('V74.0.67.2.10 provider init retry + last-error telemetry')
$backup=$null
if($needs){
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_10_1_$stamp"
    New-Item -ItemType Directory -Force -Path $backup|Out-Null
    Copy-Item -LiteralPath $bridge -Destination (Join-Path $backup 'VulkanUpscalerBridge.cs') -Force
    try{& (Join-Path $PSScriptRoot 'patch_source.ps1')}
    catch{Copy-Item -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') -Destination $bridge -Force;throw}
}else{Write-Host '[V74.0.67.2.10.1] Managed source already patched.'}

Stop-SharpEmuForBuild
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_10_1_BUILD_$stamp.log"
$cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
$old=$ErrorActionPreference
try{$ErrorActionPreference='Continue';$out=@(& dotnet build $cli -c Release -r win-x64 2>&1);$ec=$LASTEXITCODE}
finally{$ErrorActionPreference=$old}
$lines=@(foreach($item in $out){if($null-ne $item){$s=$item.ToString();Write-Host $s;$s}})
$lines|Set-Content -LiteralPath $buildLog -Encoding UTF8
if($ec-ne 0){
    if($needs -and $null-ne $backup){Copy-Item -LiteralPath (Join-Path $backup 'VulkanUpscalerBridge.cs') -Destination $bridge -Force}
    throw "SharpEmu.CLI build failed: native exit $ec"
}
$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}
$upDir=Join-Path $releaseHost.DirectoryName 'upscalers';New-Item -ItemType Directory -Force -Path $upDir|Out-Null
$deployedProvider=Join-Path $upDir 'SharpEmu.VulkanUpscaler.Native.dll'
$deployedNgx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
Copy-Item -LiteralPath $provider -Destination $deployedProvider -Force
Copy-Item -LiteralPath $ngxDll -Destination $deployedNgx -Force
Write-Host '[V74.0.67.2.10.1] APPLY + HOST BUILD + PROVIDER REDEPLOY PASSED.'
Write-Host "[V74.0.67.2.10.1] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.10.1] Provider=$deployedProvider"
Write-Host "[V74.0.67.2.10.1] NGX=$deployedNgx"
Write-Host "[V74.0.67.2.10.1] BuildLog=$buildLog"
if($null-ne $backup){Write-Host "[V74.0.67.2.10.1] Backup=$backup"}
