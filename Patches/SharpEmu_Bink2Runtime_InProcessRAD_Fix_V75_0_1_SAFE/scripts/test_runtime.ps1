param(
    [string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$statePath=Get-StatePath
if(-not(Test-Path -LiteralPath $statePath)){ throw "$script:Tag state missing; run RUN_0B and RUN_3 first" }
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
if([string]::IsNullOrWhiteSpace($state.adapter_sha256)){ throw "$script:Tag adapter not built; run RUN_3 first" }
if(-not(Test-Path -LiteralPath $state.runtime_dll)){ throw "$script:Tag runtime DLL missing: $($state.runtime_dll)" }
if(-not(Test-Path -LiteralPath $EbootPath)){ throw "$script:Tag eboot missing: $EbootPath" }

$releasePlugin=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
if(-not(Test-Path -LiteralPath $releasePlugin)){ throw "$script:Tag deployed adapter missing: $releasePlugin" }

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
foreach($name in $names){ $old[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }

$env:SHARPEMU_BINK_NATIVE_DLL=$releasePlugin
$env:SHARPEMU_BINK_RUNTIME_DLL=$state.runtime_dll
$env:SHARPEMU_BINK_MODE='rad'
$env:SHARPEMU_BINK_NATIVE_PREFER='1'
$env:SHARPEMU_BINK_NATIVE_FALLBACK='1'
if([string]::IsNullOrWhiteSpace($env:SHARPEMU_BINK_RUNTIME_SURFACE)){
    $env:SHARPEMU_BINK_RUNTIME_SURFACE='5'
}
$env:SHARPEMU_LOG_AUDIO_OUT2='1'
$env:SHARPEMU_LOG_AMPR_READS='1'

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V75_0_1_STDOUT_$stamp.tmp"
$stderr=Join-Path $patches "SharpEmu_V75_0_1_STDERR_$stamp.tmp"
$log=Join-Path $patches "SharpEmu_V75_0_1_BINK2_RUNTIME_$stamp.log"

Write-Host '[V75.0.1] TESTE NATIVE RAD:'
Write-Host '1. Boot normal ate logo_intro_loop / PRESS ANY BUTTON.'
Write-Host '2. Entre no main_menu e fique 20-30 segundos.'
Write-Host '3. Para logo_intro_loop/main_menu esperamos decoder=in-process-sdk e NENHUM radvideo64.exe.'
Write-Host '4. Videos com audio Bink embutido podem cair para external RAD; isso e intencional.'
Write-Host '5. A UI deve continuar no mesmo guest framebuffer/Vulkan, sem child HWND/GDI capture.'
Write-Host '6. Feche normalmente.'

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
'SharpEmu V75.0.1 BINK2 RUNTIME IN-PROCESS TEST',
"timestamp=$stamp",
"process_exit_code=$exitCode",
"runtime_dll=$($state.runtime_dll)",
"runtime_sha256=$($state.runtime_sha256)",
"adapter_sha256=$($state.adapter_sha256)",
'native_audio_capability=False',
'expected_ui_binks=native-rad',
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
