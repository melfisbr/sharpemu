param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot;Stop-SharpEmu
if(-not(Test-Path -LiteralPath $EbootPath -PathType Leaf)){throw "$script:Tag eboot missing: $EbootPath"}
$root=Get-ReleaseRoot;$adapter=Join-Path $root 'plugins\bink2\SharpEmu.BinkNative.dll';$ffmpeg=Join-Path $root 'plugins\bink2\ffmpeg-runtime\ffmpeg.exe'
if(-not(Test-Path $adapter)){throw "$script:Tag adapter missing; run RUN_3"};if(-not(Test-Path $ffmpeg)){throw "$script:Tag ffmpeg-core runtime missing; run RUN_4"}
$names=@('SHARPEMU_BINK_NATIVE_DLL','SHARPEMU_BINK_MODE','SHARPEMU_BINK_NATIVE_PREFER','SHARPEMU_BINK_NATIVE_FALLBACK','SHARPEMU_BINK_NATIVE_EXCLUSIVE','SHARPEMU_BINK_FFMPEG_EXE','SHARPEMU_BINK_ALLOW_PATH_FFMPEG','SHARPEMU_RADVIDEO64','SHARPEMU_LOG_AUDIO_OUT2','SHARPEMU_LOG_AMPR_READS')
$old=@{};foreach($n in $names){$old[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
$env:SHARPEMU_BINK_NATIVE_DLL=$adapter;$env:SHARPEMU_BINK_MODE='native-rad';$env:SHARPEMU_BINK_NATIVE_PREFER='1';$env:SHARPEMU_BINK_NATIVE_FALLBACK='0';$env:SHARPEMU_BINK_NATIVE_EXCLUSIVE='1';$env:SHARPEMU_BINK_FFMPEG_EXE=$ffmpeg;$env:SHARPEMU_BINK_ALLOW_PATH_FFMPEG='0';$env:SHARPEMU_RADVIDEO64=$null;$env:SHARPEMU_LOG_AUDIO_OUT2='1';$env:SHARPEMU_LOG_AMPR_READS='1'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$out=Join-Path $patches "SharpEmu_V75_0_4_3_NATIVE_AV_STDOUT_$stamp.tmp";$err=Join-Path $patches "SharpEmu_V75_0_4_3_NATIVE_AV_STDERR_$stamp.tmp";$log=Join-Path $patches "SharpEmu_V75_0_4_3_NATIVE_AV_$stamp.log";$evidence=Join-Path $patches "SharpEmu_V75_0_4_3_NATIVE_AV_EVIDENCE_$stamp.txt";$summary=Join-Path $patches "SharpEmu_V75_0_4_3_SUMMARY_$stamp.txt";$result=Join-Path $patches "SharpEmu_V75_0_4_3_RESULT_$stamp.zip"
$exe=Join-Path $root 'SharpEmu.exe';$dll=Join-Path $root 'SharpEmu.dll'
Write-Tag 'TEST START backend=native-rad + local verified ffmpeg runtime; radvideo64.exe is intentionally disabled; no Git/network operation.'
Write-Tag 'The script waits for SharpEmu to close, then consolidates evidence/result ZIP in Patches.'
$exit=-1
try{
 Push-Location $repo
 if(Test-Path $exe){$p=Start-Process $exe -ArgumentList @(('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
 else{$dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source;$p=Start-Process $dotnet -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
 $exit=$p.ExitCode
}finally{Pop-Location;foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$old[$n],'Process')}}
@("SharpEmu V75.0.4.3 NATIVE LOCAL-RUNTIME A/V + NIHAV OWNERSHIP TEST","adapter=$adapter","adapter_sha=$(Get-Sha $adapter)","ffmpeg=$ffmpeg","exit=$exit")|Set-Content -LiteralPath $log -Encoding UTF8
foreach($f in @($out,$err)){if(Test-Path $f){Get-Content $f|Add-Content $log -Encoding UTF8;Remove-Item $f -Force}}
$patterns=@('BINK-NATIVE','nihav_suppressed','legacy_nihav_route_promoted','Bink2 NIHAV bridge attached','bink2.','FIRST_VISIBLE_FRAME','MAIN_MENU_LOOP_RESTART','TITLE_TIMELINE_PASSTHROUGH','OPTIONS-SKIP','rad_required','fallback_external_rad','ffmpeg-')
Select-String -LiteralPath $log -Pattern $patterns -SimpleMatch|ForEach-Object{$_.Line}|Set-Content -LiteralPath $evidence -Encoding UTF8
$text=[IO.File]::ReadAllText($log)
$checks=[ordered]@{
 AdapterLoaded=$text.Contains('adapter_loaded');
 NativeOpenOk=$text.Contains('open_ok');
 FirstVisibleFrame=$text.Contains('[BINK-NATIVE][V75.0.4] first_visible_frame');
 ExternalRadFallbackUsed=$text.Contains('fallback_external_rad');
 RadRequiredMissing=$text.Contains('bink2.rad_required_missing');
 NativeAttachFailed=$text.Contains('[BINK-NATIVE][V75.0.0] attach_failed');
 NihavSuppressed=$text.Contains('nihav_suppressed');
 NihavAttached=$text.Contains('Bink2 NIHAV bridge attached');
 NativeExclusiveConfigured=$true;
}
$summaryLines=New-Object System.Collections.Generic.List[string];$summaryLines.Add('SharpEmu V75.0.4.3 summary');$summaryLines.Add('========================');$summaryLines.Add("Exit=$exit");foreach($kv in $checks.GetEnumerator()){$summaryLines.Add("$($kv.Key)=$($kv.Value)")};$summaryLines|Set-Content -LiteralPath $summary -Encoding UTF8
if(Test-Path $result){Remove-Item $result -Force};Compress-Archive -Path @($log,$evidence,$summary) -DestinationPath $result -CompressionLevel Optimal
Write-Tag "TEST COMPLETE exit=$exit log=$log"
Write-Tag "RESULT=$result"
