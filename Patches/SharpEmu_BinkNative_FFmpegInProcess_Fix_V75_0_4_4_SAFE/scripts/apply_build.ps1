param([switch]$SkipBuild)
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot;Stop-SharpEmu
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$stage=Join-Path $patches "SharpEmu_V75_0_4_4_BACKUP_STAGE_$stamp";$backup=Join-Path $patches "SharpEmu_V75_0_4_4_BACKUP_$stamp.zip";New-Item -ItemType Directory -Path $stage -Force|Out-Null
$changed=0
function Backup-One([string]$Path){$rel=$Path.Substring($repo.TrimEnd('\').Length).TrimStart('\');$dst=Join-Path $stage $rel;New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force|Out-Null;Copy-Item -LiteralPath $Path -Destination $dst -Force}
try{
  foreach($b in (Get-FfmpegFixedBaselines)){
    $dst=Join-Path $repo $b.Rel;$sha=Get-Sha $dst;if($sha -eq $b.Patched){continue};Backup-One $dst;$payload=Join-Path (Get-PackageRoot) ('payload\'+$b.Rel);Copy-Item -LiteralPath $payload -Destination $dst -Force;if((Get-Sha $dst) -ne $b.Patched){throw "$script:Tag payload hash mismatch: $($b.Rel)"};$changed++
  }
  $host=Join-Path $repo 'src\SharpEmu.Libs\Media\HostMovieBridge.cs';$preview=Invoke-HostFfmpegTransform -Path $host;if($preview.Changed -gt 0){Backup-One $host;$r=Invoke-HostFfmpegTransform -Path $host -Apply;$changed++;Write-Tag "HOST TRANSFORM APPLIED changes=$($r.Changed)"}else{Write-Tag 'HOST TRANSFORM ALREADY APPLIED'}
  if((Get-ChildItem $stage -Recurse -File).Count -gt 0){Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $backup -CompressionLevel Optimal -Force}
}finally{if(Test-Path $stage){Remove-Item $stage -Recurse -Force}}
if(-not$SkipBuild){
  $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj';$dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source;$buildLog=Join-Path $patches "SharpEmu_V75_0_4_4_BUILD_$stamp.log";Write-Tag "BUILD Release CLI project=$project log=$buildLog (uses fork-pinned ffmpeg runtime target)";& $dotnet build $project -c Release -r win-x64 2>&1|Tee-Object -FilePath $buildLog;if($LASTEXITCODE -ne 0){throw "$script:Tag BUILD FAILED exit=$LASTEXITCODE log=$buildLog"}
}
$backupValue=if(Test-Path -LiteralPath $backup -PathType Leaf){$backup}else{''}
$state=[ordered]@{Version='75.0.4.4';Timestamp=$stamp;RepositoryRoot=$repo;Backup=$backupValue;ChangedSourceFiles=$changed;Backend='ffmpeg-core-inprocess';NihavFallback=$false;GitMutation=$false};$state|ConvertTo-Json|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
Write-Tag "APPLY+BUILD PASSED changed=$changed backup=$($state.Backup) backend=ffmpeg-core-inprocess nihav_fallback=False"
Write-Tag 'NEXT: RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd. This downloads ONLY the official prebuilt ffmpeg-core runtime archive; no git operation touches your fork.'
