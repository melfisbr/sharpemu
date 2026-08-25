param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot;Stop-SharpEmu
if(-not(Test-Path -LiteralPath $EbootPath -PathType Leaf)){throw "$script:Tag eboot missing: $EbootPath"}
$root=Get-ReleaseRoot;$plugins=Join-Path $root 'plugins'
foreach($name in @('avcodec-61.dll','avformat-61.dll','avutil-59.dll','swscale-8.dll','swresample-5.dll')){if(-not(Test-Path -LiteralPath (Join-Path $plugins $name) -PathType Leaf)){throw "$script:Tag ffmpeg-core runtime missing $name; run RUN_4"}}
$names=@('SHARPEMU_BINK_MODE','SHARPEMU_BINK_NATIVE_PREFER','SHARPEMU_BINK_NATIVE_FALLBACK','SHARPEMU_BINK_NATIVE_EXCLUSIVE','SHARPEMU_BINK_LEGACY_ADAPTER_FALLBACK','SHARPEMU_FFMPEG_CORE_ROOT','SHARPEMU_BINK_FFMPEG_EXE','SHARPEMU_BINK_ALLOW_PATH_FFMPEG','SHARPEMU_RADVIDEO64','SHARPEMU_NIHAV_TOOL','SHARPEMU_LOG_AUDIO_OUT2','SHARPEMU_LOG_AMPR_READS')
$old=@{};foreach($n in $names){$old[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
$env:SHARPEMU_BINK_MODE='native-rad';$env:SHARPEMU_BINK_NATIVE_PREFER='1';$env:SHARPEMU_BINK_NATIVE_FALLBACK='0';$env:SHARPEMU_BINK_NATIVE_EXCLUSIVE='1';$env:SHARPEMU_BINK_LEGACY_ADAPTER_FALLBACK='0';$env:SHARPEMU_FFMPEG_CORE_ROOT=$plugins;$env:SHARPEMU_BINK_FFMPEG_EXE=$null;$env:SHARPEMU_BINK_ALLOW_PATH_FFMPEG='0';$env:SHARPEMU_RADVIDEO64=$null;$env:SHARPEMU_NIHAV_TOOL=$null;$env:SHARPEMU_LOG_AUDIO_OUT2='1';$env:SHARPEMU_LOG_AMPR_READS='1'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$out=Join-Path $patches "SharpEmu_V75_0_4_7_FFMPEG_STDOUT_$stamp.tmp";$err=Join-Path $patches "SharpEmu_V75_0_4_7_FFMPEG_STDERR_$stamp.tmp";$log=Join-Path $patches "SharpEmu_V75_0_4_7_FFMPEG_NATIVE_AV_$stamp.log";$evidence=Join-Path $patches "SharpEmu_V75_0_4_7_FFMPEG_EVIDENCE_$stamp.txt";$summary=Join-Path $patches "SharpEmu_V75_0_4_7_SUMMARY_$stamp.txt";$result=Join-Path $patches "SharpEmu_V75_0_4_7_RESULT_$stamp.zip"
$exe=Join-Path $root 'SharpEmu.exe';$dll=Join-Path $root 'SharpEmu.dll'
Write-Tag 'TEST START backend=ffmpeg-core-inprocess native DLLs; Nihav and external RAD are disabled as automatic fallbacks.'
Write-Tag 'Close SharpEmu normally after collecting the target scene; the script then creates evidence and result ZIP in Patches.'
$exit=-1
try{
 Push-Location $repo
 if(Test-Path $exe){$p=Start-Process $exe -ArgumentList @(('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
 else{$dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source;$p=Start-Process $dotnet -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
 $exit=$p.ExitCode
}finally{Pop-Location;foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$old[$n],'Process')}}
@('SharpEmu V75.0.4.5 FFMPEG-CORE IN-PROCESS A/V TEST',"plugins=$plugins","exit=$exit")|Set-Content -LiteralPath $log -Encoding UTF8
foreach($f in @($out,$err)){if(Test-Path $f){Get-Content $f|Add-Content $log -Encoding UTF8;Remove-Item $f -Force}}
$patterns=@('BINK-FFMPEG','BINK-NATIVE','nihav_suppressed','Bink2 NIHAV bridge attached','bink2.nihav_ready','fallback_external_rad','rad_required','first_visible_frame','MAIN_MENU_LOOP_RESTART','TITLE_TIMELINE_PASSTHROUGH','OPTIONS-SKIP','Bink audio disabled','audio_out2')
Select-String -LiteralPath $log -Pattern $patterns -SimpleMatch|ForEach-Object{$_.Line}|Set-Content -LiteralPath $evidence -Encoding UTF8
$text=[IO.File]::ReadAllText($log)
$checks=[ordered]@{
 FfmpegRuntimeInitialized=$text.Contains('[BINK-FFMPEG][V75.0.4.5] runtime_initialized');
 FfmpegBridgeAttached=$text.Contains('[BINK-FFMPEG][V75.0.4.5] bridge_attached');
 FirstVisibleFrame=$text.Contains('[BINK-FFMPEG][V75.0.4.5] first_visible_frame');
 FfmpegOpenException=$text.Contains('[BINK-FFMPEG][V75.0.4.5] open_exception');
 FfmpegOpenFailed=$text.Contains('[BINK-FFMPEG][V75.0.4.5] open_failed');
 NihavAttached=$text.Contains('Bink2 NIHAV bridge attached');
 NihavReady=$text.Contains('bink2.nihav_ready');
 ExternalRadFallbackUsed=$text.Contains('fallback_external_rad');
 RadRequiredMissing=$text.Contains('bink2.rad_required_missing');
}
$lines=New-Object System.Collections.Generic.List[string];$lines.Add('SharpEmu V75.0.4.5 summary');$lines.Add('========================');$lines.Add("Exit=$exit");foreach($kv in $checks.GetEnumerator()){$lines.Add("$($kv.Key)=$($kv.Value)")};$lines|Set-Content -LiteralPath $summary -Encoding UTF8
if(Test-Path $result){Remove-Item $result -Force};Compress-Archive -Path @($log,$evidence,$summary) -DestinationPath $result -CompressionLevel Optimal
Write-Tag "TEST COMPLETE exit=$exit log=$log"
Write-Tag "RESULT=$result"
