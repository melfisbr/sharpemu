param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
Stop-SharpEmu
Get-Process radvideo64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if(-not(Test-Path -LiteralPath $EbootPath -PathType Leaf)){throw "$script:Tag eboot missing: $EbootPath"}
$root=Get-ReleaseRoot
$plugins=Join-Path $root 'plugins'
foreach($name in @('avcodec-61.dll','avformat-61.dll','avutil-59.dll','swscale-8.dll','swresample-5.dll')){
  $p=Join-Path $plugins $name
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$script:Tag ffmpeg-core runtime missing $name; run RUN_4"}
  if((Get-PeMachine $p)-ne 0x8664){throw "$script:Tag ffmpeg runtime is not AMD64: $p"}
}
$names=@(
 'SHARPEMU_BINK_MODE','SHARPEMU_BINK_NATIVE_PREFER','SHARPEMU_BINK_NATIVE_FALLBACK','SHARPEMU_BINK_NATIVE_EXCLUSIVE',
 'SHARPEMU_BINK_LEGACY_ADAPTER_FALLBACK','SHARPEMU_FFMPEG_CORE_ROOT','SHARPEMU_BINK_FFMPEG_EXE','SHARPEMU_BINK_ALLOW_PATH_FFMPEG',
 'SHARPEMU_RADVIDEO64','SHARPEMU_NIHAV_TOOL','SHARPEMU_LOG_AUDIO_OUT2','SHARPEMU_LOG_AMPR_READS')
$old=@{}
foreach($n in $names){$old[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
$env:SHARPEMU_BINK_MODE='native-rad'
$env:SHARPEMU_BINK_NATIVE_PREFER='1'
$env:SHARPEMU_BINK_NATIVE_FALLBACK='0'
$env:SHARPEMU_BINK_NATIVE_EXCLUSIVE='1'
$env:SHARPEMU_BINK_LEGACY_ADAPTER_FALLBACK='0'
$env:SHARPEMU_FFMPEG_CORE_ROOT=$plugins
$env:SHARPEMU_BINK_FFMPEG_EXE=$null
$env:SHARPEMU_BINK_ALLOW_PATH_FFMPEG='0'
$env:SHARPEMU_RADVIDEO64=$null
$env:SHARPEMU_NIHAV_TOOL=$null
$env:SHARPEMU_LOG_AUDIO_OUT2='1'
$env:SHARPEMU_LOG_AMPR_READS='1'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V75_0_4_8_FFMPEG_STDOUT_$stamp.tmp"
$err=Join-Path $patches "SharpEmu_V75_0_4_8_FFMPEG_STDERR_$stamp.tmp"
$log=Join-Path $patches "SharpEmu_V75_0_4_8_FFMPEG_EXCLUSIVE_UI_$stamp.log"
$evidence=Join-Path $patches "SharpEmu_V75_0_4_8_FFMPEG_EVIDENCE_$stamp.txt"
$summary=Join-Path $patches "SharpEmu_V75_0_4_8_SUMMARY_$stamp.txt"
$result=Join-Path $patches "SharpEmu_V75_0_4_8_RESULT_$stamp.zip"
$exe=Join-Path $root 'SharpEmu.exe'
$dll=Join-Path $root 'SharpEmu.dll'
Write-Tag 'TEST START strict owner=ffmpeg-core-inprocess for fullscreen + UI BK2; automatic RAD and NIHAV paths are blocked.'
Write-Tag 'Run through PS Studios / attract / logo_intro_loop / main_menu if possible, then close SharpEmu normally.'
$exit=-1
try{
  Push-Location $repo
  if(Test-Path $exe){$p=Start-Process $exe -ArgumentList @((('"'+$EbootPath+'"'))) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
  else{$dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source;$p=Start-Process $dotnet -ArgumentList @((('"'+$dll+'"')),(('"'+$EbootPath+'"'))) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
  $exit=$p.ExitCode
}finally{
  Pop-Location
  foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$old[$n],'Process')}
}
@('SharpEmu V75.0.4.8 FFMPEG-CORE EXCLUSIVE UI/BINK TEST',"plugins=$plugins","exit=$exit")|Set-Content -LiteralPath $log -Encoding UTF8
foreach($f in @($out,$err)){if(Test-Path $f){Get-Content $f|Add-Content $log -Encoding UTF8;Remove-Item $f -Force}}
$patterns=@(
 'BINK-FFMPEG','route_locked','runtime_initialized','bridge_attached','first_visible_frame','strict_attach_failed',
 'external_rad_blocked','nihav_blocked','RAD_EXTERNAL_FORCE','RAD_EXTERNAL_FORCE_CASE','bink2.rad_required_started','radvideo64.exe',
 'Bink2 NIHAV bridge attached','bink2.nihav_ready','nihav_suppressed','logo_intro_loop.bk2','main_menu.bk2','main_menu_ngp.bk2',
 'ps_studios_logo.bk2','attract_movie.bk2','TITLE_TIMELINE_PASSTHROUGH','OPTIONS-SKIP','Bink audio disabled')
Select-String -LiteralPath $log -Pattern $patterns -SimpleMatch|ForEach-Object{$_.Line}|Set-Content -LiteralPath $evidence -Encoding UTF8
$text=[IO.File]::ReadAllText($log)
$checks=[ordered]@{
 FfmpegRuntimeInitialized=$text.Contains('[BINK-FFMPEG][V75.0.4.5] runtime_initialized')
 FfmpegBridgeAttached=$text.Contains('[BINK-FFMPEG][V75.0.4.5] bridge_attached')
 FfmpegRouteLocked=$text.Contains('[BINK-FFMPEG][V75.0.4.8] route_locked')
 FirstVisibleFrame=$text.Contains('[BINK-FFMPEG][V75.0.4.5] first_visible_frame')
 LogoIntroLoopSeen=$text.Contains("file='logo_intro_loop.bk2'")
 MainMenuSeen=$text.Contains("file='main_menu.bk2'")
 MainMenuNgpSeen=$text.Contains("file='main_menu_ngp.bk2'")
 ExternalRadStarted=$text.Contains('bink2.rad_required_started') -or $text.Contains("tool='C:\Program Files (x86)\RADVideo\radvideo64.exe'")
 ExternalRadForceExecuted=$text.Contains('[V75.0.1.3][RAD_EXTERNAL_FORCE]') -or $text.Contains('[V75.0.1.3][RAD_EXTERNAL_FORCE_CASE]')
 NihavAttached=$text.Contains('Bink2 NIHAV bridge attached')
 NihavReady=$text.Contains('bink2.nihav_ready')
 StrictAttachFailed=$text.Contains('[BINK-FFMPEG][V75.0.4.8] strict_attach_failed')
}
$strictPass=$checks.FfmpegBridgeAttached -and $checks.FfmpegRouteLocked -and -not$checks.ExternalRadStarted -and -not$checks.NihavAttached -and -not$checks.NihavReady -and -not$checks.StrictAttachFailed
$lines=New-Object System.Collections.Generic.List[string]
$lines.Add('SharpEmu V75.0.4.8 summary')
$lines.Add('========================')
$lines.Add("Exit=$exit")
foreach($kv in $checks.GetEnumerator()){$lines.Add("$($kv.Key)=$($kv.Value)")}
$lines.Add("StrictFfmpegExclusivePass=$strictPass")
$lines|Set-Content -LiteralPath $summary -Encoding UTF8
if(Test-Path $result){Remove-Item $result -Force}
Compress-Archive -Path @($log,$evidence,$summary) -DestinationPath $result -CompressionLevel Optimal
Write-Tag "TEST COMPLETE exit=$exit strict_ffmpeg_exclusive_pass=$strictPass log=$log"
Write-Tag "RESULT=$result"
