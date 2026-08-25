param([string]$RuntimeDll='')
. (Join-Path $PSScriptRoot 'common.ps1')

& (Join-Path $PSScriptRoot 'precheck.ps1')

# Probe is now informational for automatic discovery. It always creates state.
# Only an explicitly supplied incompatible DLL remains a hard error.
if(-not[string]::IsNullOrWhiteSpace($RuntimeDll)){
    & (Join-Path $PSScriptRoot 'probe_runtime.ps1') -RuntimeDll $RuntimeDll
    if($LASTEXITCODE -ne 0){
        throw "$script:Tag explicit runtime probe failed exit=$LASTEXITCODE"
    }
}else{
    & (Join-Path $PSScriptRoot 'probe_runtime.ps1')
}

$state=Read-RuntimeState
if($null -eq $state){
    throw "$script:Tag probe did not create runtime state"
}

$runtimeFound=
    $state.PSObject.Properties.Name -contains 'runtime_found' -and
    [bool]$state.runtime_found

$runtime=''
if($runtimeFound){
    $runtime=[string]$state.runtime_dll
    if(-not(Test-Path -LiteralPath $runtime -PathType Leaf)){
        Write-Tag "RecordedRuntimeMissing='$runtime'; switching to external fallback"
        $runtimeFound=$false
    }else{
        $runtimeProbe=Test-BinkRuntime $runtime
        if(-not$runtimeProbe.IsX64 -or -not$runtimeProbe.ExportsOk){
            Write-Tag "RecordedRuntimeNoLongerCompatible='$runtime'; switching to external fallback"
            $runtimeFound=$false
        }
    }
}

$vsDev=Find-VsDevCmd
if([string]::IsNullOrWhiteSpace($vsDev)){
    throw "$script:Tag Visual Studio C++ x64 Build Tools not found"
}

$stage=Join-Path $script:PackageRoot '.native-stage'
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$source=Get-AdapterSource
$output=Join-Path $stage 'SharpEmu.BinkNative.dll'
$object=Join-Path $stage 'SharpEmu.BinkNative.Runtime.obj'
$cmd=Join-Path $stage 'build_runtime_adapter.cmd'

$command=@"
@echo off
call "$vsDev" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b %errorlevel%
cl.exe /nologo /LD /O2 /EHsc /std:c++20 /utf-8 /Fo"$object" "$source" /link /OUT:"$output"
exit /b %errorlevel%
"@
Set-Content -LiteralPath $cmd -Value $command -Encoding ASCII

Write-Tag "RuntimeFound=$runtimeFound"
if($runtimeFound){
    Write-Tag "RuntimeDll=$runtime"
    Write-Tag "RuntimeSHA256=$(Get-Sha $runtime)"
}else{
    Write-Tag 'RuntimeDll=NONE'
    Write-Tag 'BuildPolicy=adapter-build-without-runtime'
    Write-Tag 'FallbackPolicy=external-rad-preserved'
}
Write-Tag "VsDevCmd=$vsDev"

& cmd.exe /d /s /c "`"$cmd`""
if($LASTEXITCODE -ne 0){
    throw "$script:Tag adapter build failed exit=$LASTEXITCODE"
}
if(-not(Test-Path -LiteralPath $output -PathType Leaf)){
    throw "$script:Tag adapter build reported success but DLL missing"
}

$deployedAdapterPaths=@()
$deployedRuntimePaths=@()
foreach($dir in @(Get-DeployDirs)){
    New-Item -ItemType Directory -Path $dir -Force|Out-Null

    $adapterDestination=Join-Path $dir 'SharpEmu.BinkNative.dll'
    Copy-Item -LiteralPath $output -Destination $adapterDestination -Force
    $deployedAdapterPaths += $adapterDestination

    if($runtimeFound){
        $runtimeDestination=Join-Path $dir 'bink2w64.dll'
        $sourceFull=[IO.Path]::GetFullPath($runtime)
        $destinationFull=[IO.Path]::GetFullPath($runtimeDestination)
        if(-not[string]::Equals(
            $sourceFull,
            $destinationFull,
            [StringComparison]::OrdinalIgnoreCase)){
            Copy-Item -LiteralPath $runtime -Destination $runtimeDestination -Force
        }
        $deployedRuntimePaths += $runtimeDestination
    }
}

$values=@{
    adapter_sha256=(Get-Sha $output)
    adapter_path=$output
    adapter_deployed_paths=$deployedAdapterPaths
    adapter_ready=$true
    built_at=(Get-Date).ToString('o')
}
if($runtimeFound){
    $values['runtime_found']=$true
    $values['runtime_dll']=$runtime
    $values['runtime_sha256']=Get-Sha $runtime
    $values['runtime_deployed_paths']=$deployedRuntimePaths
    $values['runtime_mode']='native-rad-ready'
}else{
    $values['runtime_found']=$false
    $values['runtime_dll']=''
    $values['runtime_sha256']=''
    $values['runtime_deployed_paths']=@()
    $values['runtime_mode']='external-rad-fallback'
}
$state=Write-RuntimeState $values

Write-Tag "AdapterSHA256=$($state.adapter_sha256)"
Write-Tag "AdapterDeployCount=$($deployedAdapterPaths.Count)"
if($runtimeFound){
    Write-Tag "RuntimeDeployCount=$($deployedRuntimePaths.Count)"
    Write-Tag 'NativeRAD=READY'
}else{
    Write-Tag 'NativeRAD=WAITING_FOR_USER_RUNTIME'
    Write-Tag 'ExternalRADFallback=READY'
}
Write-Tag 'BUILD/DEPLOY PASSED'
