param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$statePath=Get-StatePath

if(-not(Test-Path -LiteralPath $statePath)){
    throw "$script:Tag install state missing; run RUN_3 first"
}
if(-not(Test-Path -LiteralPath $EbootPath)){
    throw "$script:Tag eboot missing: $EbootPath"
}
if((Get-Sha (Join-Path $repo $script:RelativeHostApi)) -ne $script:PayloadHostApiSha){
    throw "$script:Tag installed HostApi changed"
}
if((Get-Sha (Join-Path $repo $script:RelativePresenter)) -ne $script:PayloadPresenterSha){
    throw "$script:Tag installed Presenter changed"
}

$envNames=@(
'SHARPEMU_RADVIDEO64',
'SHARPEMU_BINK_MODE',
'SHARPEMU_BINK_NATIVE_PREFER',
'SHARPEMU_RAD_PLAYER_INPUT_LOCK',
'SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE',
'SHARPEMU_DS_UI_BINK_INTERNAL',
'SHARPEMU_DS_RAD_UI_NATIVE_LOOP_SYNC',
'SHARPEMU_DS_RAD_UI_SWAPCHAIN_CONTINUITY',
'SHARPEMU_DS_RAD_UI_TEXTURE_CAPTURE',
'SHARPEMU_DS_RAD_UI_TEXTURE_CAPTURE_FPS',
'SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_COMPOSITE',
'SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_EXPERIMENTAL',
'SHARPEMU_DS_RAD_UI_NEUTRAL_YUV',
'SHARPEMU_LOG_AUDIO_OUT2',
'SHARPEMU_LOG_AMPR_READS'
)
$oldEnv=@{}
foreach($name in $envNames){
    $oldEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
}
Set-TestEnvironment

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_STDOUT_$stamp.tmp"
$stderr=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_STDERR_$stamp.tmp"
$log=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_RAD_TEXTURE_UI_$stamp.log"

Write-Host '[V118.7.6.3.12] TESTE VISUAL:'
Write-Host '1. No logo_intro_loop, PRESS ANY BUTTON deve voltar sobre o Bink em tela cheia.'
Write-Host '2. Entre no main_menu e permaneça 20-30 segundos.'
Write-Host '3. A estatua/Bink deve permanecer tela cheia e estavel, sem sumir/reaparecer.'
Write-Host '4. CONTINUE / LOAD GAME / NEW GAME / SETTINGS / GALLERY e copyright devem vir da UI guest.'
Write-Host '5. Nao deve existir placa preta/verde, recorte de 34%, nem Bink VIDEO na taskbar.'
Write-Host '6. Feche o SharpEmu normalmente e rode RUN_5.'

$exe=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe'
$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'

$runtimeExit=-1
try{
    Push-Location $repo
    if(Test-Path -LiteralPath $exe){
        $proc=Start-Process -FilePath $exe -ArgumentList @(('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    }else{
        $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
        $proc=Start-Process -FilePath $dotnet -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    }
    $runtimeExit=$proc.ExitCode
}finally{
    Pop-Location
    foreach($name in $envNames){
        [Environment]::SetEnvironmentVariable($name,$oldEnv[$name],'Process')
    }
}

@(
'SharpEmu V74.0.118.7.6.3.12 RAD UI PS5 TEXTURE COMPOSE TEST',
"timestamp=$stamp",
"process_exit_code=$runtimeExit",
'preferred_decoder=native-rad-if-licensed-adapter-available',
'fallback_decoder=official-rad-external',
'external_rad_role=decoder-and-texture-source-only',
'ui_binks=logo_intro_loop.bk2;main_menu.bk2;main_menu_ngp.bk2',
'final_owner=guest-vulkan-swapchain',
'descriptorless_ui_policy=keep-guest-frame',
'legacy_direct_composite=disabled',
'analyzer_policy=visual-success-required'
)|Set-Content -LiteralPath $log -Encoding UTF8

foreach($path in @($stdout,$stderr)){
    if(Test-Path -LiteralPath $path){
        Get-Content -LiteralPath $path|Add-Content -LiteralPath $log -Encoding UTF8
        Remove-Item -LiteralPath $path -Force
    }
}
Write-Tag "TEST COMPLETE exit=$runtimeExit log=$log"
