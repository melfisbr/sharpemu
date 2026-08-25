param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot; $patches=Get-PatchesRoot
if(-not(Test-Path -LiteralPath (Get-StatePath))){throw "$script:Tag install state missing; run RUN_3 first"}
if(-not(Test-Path -LiteralPath $EbootPath)){throw "$script:Tag eboot missing: $EbootPath"}
$state=Get-BaselineState
if($state.State -ne 'installed'){throw "$script:Tag source is not V3.12 installed state"}
$names=@('SHARPEMU_RADVIDEO64','SHARPEMU_BINK_MODE','SHARPEMU_BINK_NATIVE_PREFER','SHARPEMU_RAD_PLAYER_INPUT_LOCK','SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE','SHARPEMU_DS_UI_BINK_INTERNAL','SHARPEMU_DS_RAD_UI_NATIVE_LOOP_SYNC','SHARPEMU_DS_RAD_UI_TEXTURE_INJECTION','SHARPEMU_DS_RAD_UI_TEXTURE_CAPTURE_FPS','SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_COMPOSITE','SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_EXPERIMENTAL','SHARPEMU_DS_RAD_UI_NEUTRAL_YUV','SHARPEMU_DS_UI_BINK_CHROMA_ORDER','SHARPEMU_DS_RAD_UI_SWAPCHAIN_CONTINUITY','SHARPEMU_LOG_AUDIO_OUT2','SHARPEMU_LOG_AMPR_READS')
$old=@{}; foreach($name in $names){$old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Set-TestEnvironment
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_2_STDOUT_$stamp.tmp"; $stderr=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_2_STDERR_$stamp.tmp"; $log=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_2_GUEST_TEXTURE_UI_$stamp.log"
Write-Host '[V3.12] TESTE VISUAL ESTRUTURAL:'
Write-Host '1. No logo_intro_loop: o Bink deve ficar em tela cheia e PRESS ANY BUTTON deve ser UI guest normal.'
Write-Host '2. Nao deve surgir logo gigante por fallback descriptorless.'
Write-Host '3. Entre no main_menu e permaneça 20-30 s: estatua/video full-frame + textos/botoes/caixas nativos do guest.'
Write-Host '4. Nenhum recorte preto de 34% no lado esquerdo; nenhum compositor black-key depois do VideoOut.'
Write-Host '5. O executavel RAD nao deve aparecer na taskbar.'
Write-Host '6. Feche SharpEmu normalmente e execute RUN_5.'
$exe=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe'; $dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'; $exitCode=-1
try{
 Push-Location $repo
 if(Test-Path -LiteralPath $exe){$proc=Start-Process -FilePath $exe -ArgumentList @(('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait}
 else{$dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source;$proc=Start-Process -FilePath $dotnet -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait}
 $exitCode=$proc.ExitCode
}finally{Pop-Location;foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$old[$name],'Process')}}
@('SharpEmu V74.0.118.7.6.3.12 GUEST TEXTURE UI TEST',"timestamp=$stamp","process_exit_code=$exitCode",'decoder=official-rad-external','integration=official-rad-frame-source-to-guest-bink-yuv','final_owner=sceVideoOutSubmitFlip/guest-vulkan','neutral_yuv=disabled','post_videoout_composite=disabled','rectangular_child_region=disabled','descriptorless_direct_fallback=disabled-for-ui','chroma=UV','analyzer_policy=visual-success-required')|Set-Content -LiteralPath $log -Encoding UTF8
foreach($path in @($stdout,$stderr)){if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path|Add-Content -LiteralPath $log -Encoding UTF8;Remove-Item -LiteralPath $path -Force}}
Write-Tag "TEST COMPLETE exit=$exitCode log=$log"
