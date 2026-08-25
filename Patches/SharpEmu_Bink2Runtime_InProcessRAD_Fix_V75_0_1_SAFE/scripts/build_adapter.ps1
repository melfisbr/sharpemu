param([string]$RuntimeDll='')
. (Join-Path $PSScriptRoot 'common.ps1')

& (Join-Path $PSScriptRoot 'precheck.ps1')

if(-not[string]::IsNullOrWhiteSpace($RuntimeDll)){
    & (Join-Path $PSScriptRoot 'probe_runtime.ps1') -RuntimeDll $RuntimeDll
}
elseif(-not(Test-Path -LiteralPath (Get-StatePath))){
    & (Join-Path $PSScriptRoot 'probe_runtime.ps1')
}

$state=Get-Content -LiteralPath (Get-StatePath) -Raw|ConvertFrom-Json
$runtime=$state.runtime_dll
if(-not(Test-Path -LiteralPath $runtime -PathType Leaf)){
    throw "$script:Tag recorded runtime missing: $runtime"
}

$probe=Test-BinkRuntime $runtime
if(-not$probe.IsX64 -or -not$probe.ExportsOk){
    throw "$script:Tag recorded runtime is no longer compatible: $runtime"
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

Write-Tag "RuntimeDll=$runtime"
Write-Tag "RuntimeSHA256=$(Get-Sha $runtime)"
Write-Tag "VsDevCmd=$vsDev"

& cmd.exe /d /s /c "`"$cmd`""
if($LASTEXITCODE -ne 0){
    throw "$script:Tag adapter build failed exit=$LASTEXITCODE"
}
if(-not(Test-Path -LiteralPath $output -PathType Leaf)){
    throw "$script:Tag adapter build reported success but DLL missing"
}

foreach($dir in @(Get-DeployDirs)){
    New-Item -ItemType Directory -Path $dir -Force|Out-Null
    Copy-Item -LiteralPath $output -Destination (Join-Path $dir 'SharpEmu.BinkNative.dll') -Force
}

$state.adapter_sha256=Get-Sha $output
$state.adapter_path=$output
$state.built_at=(Get-Date).ToString('o')
$state|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8

Write-Tag "AdapterSHA256=$($state.adapter_sha256)"
Write-Tag 'BUILD/DEPLOY PASSED'
