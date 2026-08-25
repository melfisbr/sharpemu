param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
if(-not(Test-Path -LiteralPath (Get-StatePath) -PathType Leaf)){
    throw "$script:Tag install state missing; run RUN_3 first"
}
if(-not(Test-Path -LiteralPath $EbootPath -PathType Leaf)){
    throw "$script:Tag eboot missing: $EbootPath"
}

$s=Get-CurrentState
$hostText=[IO.File]::ReadAllText($s.Host)
if(-not$hostText.Contains('SHARPEMU_V75_0_1_3_EXTERNAL_RAD_COMPATIBILITY_FORCE')){
    throw "$script:Tag V75.0.1.3 HostMovieBridge marker missing"
}
if(-not$s.HasPixelLayout -or -not$s.HasPixelLayoutSource){
    throw "$script:Tag MediaFramePixelLayout compatibility contracts missing"
}
$adapterCount=@(Get-NativeAdapterPaths|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}).Count
if($adapterCount -ne 0){
    throw "$script:Tag native adapter still deployed count=$adapterCount"
}

$names=@(
'SHARPEMU_RADVIDEO64','SHARPEMU_BINK_MODE','SHARPEMU_BINK_NATIVE_PREFER',
'SHARPEMU_BINK_NATIVE_FALLBACK','SHARPEMU_BINK_NATIVE_DLL',
'SHARPEMU_BINK_RUNTIME_DLL','SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE',
'SHARPEMU_DS_UI_BINK_INTERNAL','SHARPEMU_LOG_AUDIO_OUT2','SHARPEMU_LOG_AMPR_READS')
$old=@{}
foreach($name in $names){$old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Set-ExternalRadEnvironment

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V75_0_1_3_STDOUT_$stamp.tmp"
$stderr=Join-Path $patches "SharpEmu_V75_0_1_3_STDERR_$stamp.tmp"
$log=Join-Path $patches "SharpEmu_V75_0_1_3_EXTERNAL_RAD_$stamp.log"

Write-Host '[V75.0.1.3] TESTE RAD EXTERNO COMPATIVEL:'
Write-Host '1. Passe pelos Binks ate main_menu.'
Write-Host '2. Deve existir [LOADER][INFO] Bink RAD bridge attached.'
Write-Host '3. Nao deve existir [BINK-NATIVE][V75.0.0] auto_selected/bridge_attached/open_failed/attach_failed.'
Write-Host '4. Nao deve carregar SharpEmu.BinkNative.dll.'
Write-Host '5. Feche normalmente depois de observar main_menu.'

$exe=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe'
$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'
$processExit=-1
try{
    Push-Location $repo
    if(Test-Path -LiteralPath $exe -PathType Leaf){
        $proc=Start-Process -FilePath $exe -ArgumentList @(('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    }else{
        if(-not(Test-Path -LiteralPath $dll -PathType Leaf)){throw "$script:Tag Release executable missing"}
        $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
        $proc=Start-Process -FilePath $dotnet -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    }
    $processExit=$proc.ExitCode
}finally{
    Pop-Location
    foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$old[$name],'Process')}
}

@(
'SharpEmu V75.0.1.3 EXTERNAL RAD COMPATIBILITY TEST',
"timestamp=$stamp",
"process_exit_code=$processExit",
'target_mode=official-external-rad',
'native_route=source-disabled',
'native_adapter=removed',
'MediaFramePlayback=preserved-current',
'managed_native_sources=retained-compile-only'
)|Set-Content -LiteralPath $log -Encoding UTF8

foreach($path in @($stdout,$stderr)){
    if(Test-Path -LiteralPath $path -PathType Leaf){
        Get-Content -LiteralPath $path|Add-Content -LiteralPath $log -Encoding UTF8
        Remove-Item -LiteralPath $path -Force
    }
}
Write-Tag "TEST COMPLETE exit=$processExit log=$log"
