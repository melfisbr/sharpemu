param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=Join-Path $Patches ("V76_3_19_0_PRE_SOURCE_$stamp")
$backupZip=Join-Path $Patches ("V76_3_19_0_PRE_SOURCE_$stamp.zip")
$restoreLog=Join-Path $Patches ("V76_3_19_0_DEV_RESTORE_$stamp.log")
$buildLog=Join-Path $Patches ("V76_3_19_0_DEV_BUILD_$stamp.log")

$bt=Join-Path $backupRoot $TranslatorRel
$bc=Join-Path $backupRoot $CliRel
New-Item -ItemType Directory -Force -Path (Split-Path $bt -Parent)|Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $bc -Parent)|Out-Null
Copy-Item $TranslatorPath $bt -Force
Copy-Item $CliPath $bc -Force
Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force

function Restore-Source{
 Copy-Item $bt $TranslatorPath -Force
 Copy-Item $bc $CliPath -Force
}

try{
 $c=Read-Utf8Preserve $TranslatorPath
 $t=$c.Text
 if(-not$t.Contains('V76.3.19.0_SHADER_FRONTEND_SET_ASSOC_L2')){
  $oldCache=[IO.File]::ReadAllText((Join-Path $PackageRoot 'fragments\old_cache.txt'))
  $newCache=[IO.File]::ReadAllText((Join-Path $PackageRoot 'fragments\new_cache.txt'))
  $oldMethods=[IO.File]::ReadAllText((Join-Path $PackageRoot 'fragments\old_methods.txt'))
  $newMethods=[IO.File]::ReadAllText((Join-Path $PackageRoot 'fragments\new_methods.txt'))

  $nl=if($t.Contains("`r`n")){"`r`n"}else{"`n"}
  foreach($v in @('oldCache','newCache','oldMethods','newMethods')){
   $x=Get-Variable $v -ValueOnly
   $x=$x.Replace("`r`n","`n").Replace("`r","`n")
   if($nl-eq"`r`n"){$x=$x.Replace("`n","`r`n")}
   Set-Variable $v $x
  }

  if(-not$t.Contains($oldCache)){Fail 'translator cache block divergente'}
  if(-not$t.Contains($oldMethods)){Fail 'translator L2 methods block divergente'}

  $t=$t.Replace($oldCache,$newCache)
  $t=$t.Replace($oldMethods,$newMethods)
  Write-Utf8Preserve $TranslatorPath $t $c.HasBom
 }

 $tc=[IO.File]::ReadAllText($TranslatorPath)
 foreach($m in @(
  'V76.3.19.0_SHADER_FRONTEND_SET_ASSOC_L2',
  'V190ThreadCacheWays = 4',
  'SHARPEMU_SHADER_THREAD_CACHE_SETS_V190',
  'V190ProgramSetAssocHits',
  'V190MetadataSetAssocHits'
 )){if(-not$tc.Contains($m)){Fail "translator post-contract ausente: $m"}}

 # Final authoritative V19 hotset policy after the V18 merge block.
 $cc=Read-Utf8Preserve $CliPath
 $cli=$cc.Text
 if(-not$cli.Contains('[V76.3.19.0][SHADER_FRONTEND_HOTSET_PROFILE]')){
  $needle='"[V76.3.18.0][RPCS3_QUEUE_MERGE] " +'
  $pos=$cli.IndexOf($needle,[StringComparison]::Ordinal)
  if($pos-lt0){Fail 'V18 merge marker ausente'}
  $start=$cli.LastIndexOf('        Console.Error.WriteLine(',$pos,[StringComparison]::Ordinal)
  if($start-lt0){Fail 'V18 Console marker ausente'}
  $nl=if($cli.Contains("`r`n")){"`r`n"}else{"`n"}

  $block=@(
   '        // V76.3.19.0 - shader frontend hotset.',
   '        // Decode/metadata caches use exact keys; set-associative L2 reduces',
   '        // shared-cache lock traffic. Read-only globals retain generation',
   '        // validation but enter DEVICE_LOCAL residency sooner after reuse.',
   '        Set("SHARPEMU_SHADER_THREAD_CACHE_SETS_V190", "4096");',
   '        Set("SHARPEMU_SHADER_DECODE_CACHE_MAX", "8192");',
   '        Set("SHARPEMU_SHADER_METADATA_CACHE_MAX", "8192");',
   '        Set("SHARPEMU_SHADER_SINGLEFLIGHT_V1190", "1");',
   '        Set("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE", "1");',
   '        Set("SHARPEMU_SHADER_DEFER_GLOBAL_READS", "1");',
   '        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");',
   '        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");',
   '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");',
   '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "384");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "640");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");',
   '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_REBAR_PAUSE_FALLBACKS", "32");',
   '        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");',
   '        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "192");',
   '',
   '        Console.Error.WriteLine(',
   '            "[V76.3.19.0][SHADER_FRONTEND_HOTSET_PROFILE] " +',
   '            "l2=4wayx4096sets decode=8192 metadata=8192 " +',
   '            "resident_shader=2048 descriptor_sets=4096 " +',
   '            "global_residency=640/384MB admit=3 medium=2 large=2 " +',
   '            "deferred_globals=1 rebar=1 host_buffer_cache_mb=192 " +',
   '            "V18_queue_merge=preserved");',
   ''
  ) -join $nl
  $cli=$cli.Insert($start,$block)
  Write-Utf8Preserve $CliPath $cli $cc.HasBom
 }

 $check=[IO.File]::ReadAllText($CliPath)
 foreach($m in @(
  '[V76.3.19.0][SHADER_FRONTEND_HOTSET_PROFILE]',
  'Set("SHARPEMU_SHADER_THREAD_CACHE_SETS_V190", "4096");',
  'Set("SHARPEMU_SHADER_DECODE_CACHE_MAX", "8192");',
  'Set("SHARPEMU_SHADER_METADATA_CACHE_MAX", "8192");',
  'Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");',
  'Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");',
  'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "384");',
  'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "640");',
  'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");',
  '[V76.3.18.0][RPCS3_QUEUE_MERGE]'
 )){if(-not$check.Contains($m)){Fail "CLI post-contract ausente: $m"}}

 Push-Location $Repo
 try{
  & dotnet restore $Project -r win-x64 *>&1|Tee-Object -FilePath $restoreLog
  if($LASTEXITCODE-ne0){throw "restore falhou exit=$LASTEXITCODE"}
  & dotnet build $Project -c Debug -r win-x64 --no-restore *>&1|Tee-Object -FilePath $buildLog
  if($LASTEXITCODE-ne0){throw "build Debug falhou exit=$LASTEXITCODE"}
 }finally{Pop-Location}

 Write-Host "[$Tag] APPLY+BUILD PASSED configuration=Debug"
 Write-Host "[$Tag] translator_sha256=$(Get-HashLower $TranslatorPath)"
 Write-Host "[$Tag] cli_sha256=$(Get-HashLower $CliPath)"
 Write-Host "[$Tag] backup=$backupZip"
 Write-Host "[$Tag] build_log=$buildLog"
}catch{
 Restore-Source
 Write-Host "[$Tag] rollback=completed backup=$backupZip" -ForegroundColor Yellow
 throw
}finally{
 if(Test-Path $backupRoot){Remove-Item $backupRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
