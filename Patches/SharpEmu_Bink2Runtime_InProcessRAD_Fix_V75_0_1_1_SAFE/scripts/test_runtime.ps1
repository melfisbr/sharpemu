param(
    [string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$statePath=Get-StatePath
if(-not(Test-Path -LiteralPath $statePath)){
    throw "$script:Tag state missing; run RUN_3 first"
}
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
if(-not($state.PSObject.Properties.Name -contains 'adapter_sha256') -or
   [string]::IsNullOrWhiteSpace([string]$state.adapter_sha256)){
    throw "$script:Tag adapter not built; run RUN_3 first"
}
if(-not(Test-Path -LiteralPath $EbootPath)){
    throw "$script:Tag eboot missing: $EbootPath"
}

$releasePlugin=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
if(-not(Test-Path -LiteralPath $releasePlugin)){
    throw "$script:Tag deployed adapter missing: $releasePlugin"
}

$runtimeFound=
    $state.PSObject.Properties.Name -contains 'runtime_found' -and
    [bool]$state.runtime_found
$runtime=''
if($runtimeFound){
    $runtime=[string]$state.runtime_dll
    if(-not(Test-Path -LiteralPath $runtime -PathType Leaf)){
        $runtimeFound=$false
        $runtime=''
    }
}

$names=@(
'SHARPEMU_BINK_NATIVE_DLL',
'SHARPEMU_BINK_RUNTIME_DLL',
'SHARPEMU_BINK_MODE',
'SHARPEMU_BINK_NATIVE_PREFER',
'SHARPEMU_BINK_NATIVE_FALLBACK',
'SHARPEMU_BINK_RUNTIME_SURFACE',
'SHARPEMU_LOG_AUDIO_OUT2',
'SHARPEMU_LOG_AMPR_READS')
$old=@{}
foreach($name in $names){
    $old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
}

$env:SHARPEMU_BINK_NATIVE_DLL=$releasePlugin
if($runtimeFound){
    $env:SHARPEMU_BINK_RUNTIME_DLL=$runtime
}else{
    Remove-Item Env:SHARPEMU_BINK_RUNTIME_DLL -ErrorAction SilentlyContinue
}
$env:SHARPEMU_BINK_MODE='rad'
$env:SHARPEMU_BINK_NATIVE_PREFER='1'
$env:SHARPEMU_BINK_NATIVE_FALLBACK='1'
if([string]::IsNullOrWhiteSpace($env:SHARPEMU_BINK_RUNTIME_SURFACE)){
    $env:SHARPEMU_BINK_RUNTIME_SURFACE='5'
}
$env:SHARPEMU_LOG_AUDIO_OUT2='1'
$env:SHARPEMU_LOG_AMPR_READS='1'

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V75_0_1_1_STDOUT_$stamp.tmp"
$stderr=Join-Path $patches "SharpEmu_V75_0_1_1_STDERR_$stamp.tmp"
$log=Join-Path $patches "SharpEmu_V75_0_1_1_BINK2_RUNTIME_$stamp.log"

Write-Host '[V75.0.1.1] TESTE RAD:'
Write-Host "RuntimeFound=$runtimeFound"
if($runtimeFound){
    Write-Host '1. Esperamos logo_intro_loop/main_menu com decoder=in-process-sdk.'
    Write-Host '2. Para esses Binks de zero audio embutido, nao deve existir radvideo64.exe.'
    Write-Host '3. A UI permanece no mesmo guest framebuffer/Vulkan.'
}else{
    Write-Host '1. O adapter foi construido, mas nenhum runtime Bink2 x64 foi encontrado.'
    Write-Host '2. O teste confirmara apenas que o fallback RAD externo continua funcionando.'
    Write-Host '3. Para obter decoder=in-process-sdk, forneca um bink2w64.dll x64 compativel.'
}
Write-Host '4. Feche normalmente depois de chegar ao main_menu.'

$exe=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe'
$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'
$exitCode=-1
try{
    Push-Location $repo
    if(Test-Path -LiteralPath $exe){
        $proc=Start-Process -FilePath $exe -ArgumentList @(('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    }else{
        $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
        $proc=Start-Process -FilePath $dotnet -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    }
    $exitCode=$proc.ExitCode
}finally{
    Pop-Location
    foreach($name in $names){
        [Environment]::SetEnvironmentVariable($name,$old[$name],'Process')
    }
}

@(
'SharpEmu V75.0.1.1 BINK2 RUNTIME IN-PROCESS/FALLBACK TEST',
"timestamp=$stamp",
"process_exit_code=$exitCode",
"runtime_found=$runtimeFound",
"runtime_dll=$runtime",
"runtime_sha256=$(if($runtimeFound){$state.runtime_sha256}else{''})",
"adapter_sha256=$($state.adapter_sha256)",
"runtime_mode=$($state.runtime_mode)",
'native_audio_capability=False',
'embedded_audio_movies=external-rad-fallback-allowed',
'surface_default=5'
)|Set-Content -LiteralPath $log -Encoding UTF8

foreach($path in @($stdout,$stderr)){
    if(Test-Path -LiteralPath $path){
        Get-Content -LiteralPath $path|Add-Content -LiteralPath $log -Encoding UTF8
        Remove-Item -LiteralPath $path -Force
    }
}
Write-Tag "TEST COMPLETE exit=$exitCode log=$log"
