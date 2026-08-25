param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
Stop-SharpEmu
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stage=Join-Path $patches "SharpEmu_V75_0_4_10_BACKUP_STAGE_$stamp"
$backup=Join-Path $patches "SharpEmu_V75_0_4_10_BACKUP_$stamp.zip"
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$changed=0
function Backup-One([string]$Path){
  $rel=$Path.Substring($repo.TrimEnd('\').Length).TrimStart('\')
  $dst=Join-Path $stage $rel
  New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force|Out-Null
  Copy-Item -LiteralPath $Path -Destination $dst -Force
}
try{
  foreach($b in (Get-FfmpegFixedBaselines)){
    $dst=Join-Path $repo $b.Rel
    $sha=Get-Sha $dst
    if($sha -ne $b.Patched -and $sha -ne $b.Original -and $sha -ne $b.Prior){throw "$script:Tag source changed after precheck: $($b.Rel) sha=$sha"}
    # V75.0.4.9: always snapshot the current relevant source, including ALREADY_APPLIED state.
    Backup-One $dst
    if($sha -eq $b.Patched){continue}
    $payload=Join-Path (Get-PackageRoot) ('payload\'+$b.Rel)
    Copy-Item -LiteralPath $payload -Destination $dst -Force
    if((Get-Sha $dst) -ne $b.Patched){throw "$script:Tag payload hash mismatch: $($b.Rel)"}
    $changed++
  }

  $hostMoviePath=Join-Path $repo 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
  $beforeHost=[IO.File]::ReadAllText($hostMoviePath)
  $needHost=(-not $beforeHost.Contains('SHARPEMU_BINK_FFMPEG_INPROCESS_HOST_V75_0_4_5')) -or (-not $beforeHost.Contains('SHARPEMU_BINK_FFMPEG_EXCLUSIVE_ROUTE_V75_0_4_8'))
  # Snapshot HostMovieBridge even when V75.0.4.8 markers are already present.
  Backup-One $hostMoviePath
  $ff=Invoke-HostFfmpegTransform -Path $hostMoviePath -Apply
  $exclusive=Invoke-FfmpegExclusiveRouteTransformV75048 -Path $hostMoviePath -Apply
  $fresh=Invoke-PostStudiosFreshFrameHandoffV75049 -Path $hostMoviePath -Apply
  if($ff.Changed -gt 0 -or $exclusive.Changed -gt 0 -or $fresh.Changed -gt 0){$changed++;Write-Tag "HOST TRANSFORM APPLIED ffmpeg_changes=$($ff.Changed) exclusive_route_changes=$($exclusive.Changed) post_studios_fresh_changes=$($fresh.Changed)"}
  else{Write-Tag 'HOST TRANSFORM ALREADY APPLIED'}



  $assistPath=Join-Path $repo 'src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs'
  Backup-One $assistPath
  $guestLive=Invoke-PsStudiosGuestLiveTransformV750410 -Path $assistPath -Apply
  if($guestLive.Changed -gt 0){$changed++;Write-Tag "BINK ASSIST TRANSFORM APPLIED ps_studios_guest_live_changes=$($guestLive.Changed)"}
  else{Write-Tag 'BINK ASSIST TRANSFORM ALREADY APPLIED'}

  if(@(Get-ChildItem $stage -Recurse -File).Count -gt 0){Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $backup -CompressionLevel Optimal -Force}
}finally{if(Test-Path $stage){Remove-Item $stage -Recurse -Force}}

if(-not $SkipBuild){
  $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
  $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
  $buildLog=Join-Path $patches "SharpEmu_V75_0_4_10_BUILD_$stamp.log"
  Write-Tag "BUILD Release CLI project=$project log=$buildLog"
  & $dotnet build $project -c Release -r win-x64 2>&1|Tee-Object -FilePath $buildLog
  if($LASTEXITCODE -ne 0){throw "$script:Tag BUILD FAILED exit=$LASTEXITCODE log=$buildLog"}
}
$backupValue=if(Test-Path -LiteralPath $backup -PathType Leaf){$backup}else{''}
$state=[ordered]@{
  Version='75.0.4.10';Timestamp=$stamp;RepositoryRoot=$repo;Backup=$backupValue;ChangedSourceFiles=$changed;
  Backend='ffmpeg-core-inprocess';UiBinks='ffmpeg-core-inprocess';PostStudiosHandoff='fresh-guest-frame';PsStudiosGuestExecution='live-passthrough';ExternalRadNormalRoute=$false;NihavNormalRoute=$false;GitMutation=$false
}
$state|ConvertTo-Json|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
Write-Tag "APPLY+BUILD PASSED changed=$changed backup=$($state.Backup) backend=ffmpeg-core-inprocess ui_binks=ffmpeg post_studios_handoff=fresh-guest-frame ps_studios_guest_execution=live external_rad_normal_route=False nihav_normal_route=False"
Write-Tag 'NEXT: RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd (reuses the already-installed runtime when present).'
