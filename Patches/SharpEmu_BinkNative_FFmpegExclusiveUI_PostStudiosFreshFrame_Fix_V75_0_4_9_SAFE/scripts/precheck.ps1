$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
Assert-FfmpegAbiMatch
Test-OwnershipPrerequisites $repo
$ready=0;$applied=0
foreach($b in (Get-FfmpegFixedBaselines)){
  $p=Join-Path $repo $b.Rel
  if(-not(Test-Path $p)){throw "$script:Tag missing source: $($b.Rel)"}
  $sha=Get-Sha $p
  if($sha -eq $b.Original){$ready++;Write-Tag "READY $($b.Rel) sha=$sha"}
  elseif($sha -eq $b.Prior){$ready++;Write-Tag "READY_UPGRADE_FROM_V75.0.4.4 $($b.Rel) sha=$sha"}
  elseif($sha -eq $b.Patched){$applied++;Write-Tag "ALREADY_APPLIED $($b.Rel) sha=$sha"}
  else{throw "$script:Tag DIVERGENT source=$($b.Rel) sha=$sha expected_original=$($b.Original) expected_prior=$($b.Prior) expected_patched=$($b.Patched)"}
}
$hostMoviePath=Join-Path $repo 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$hostText=[IO.File]::ReadAllText($hostMoviePath)
$forceMarker=$hostText.Contains('[V75.0.1.3][RAD_EXTERNAL_FORCE]') -or $hostText.Contains('[V75.0.1.3][RAD_EXTERNAL_FORCE_CASE]')
$temp=Join-Path $env:TEMP ("SharpEmu_V750481_Precheck_"+[Guid]::NewGuid().ToString('N')+'.cs')
try{
  Copy-Item -LiteralPath $hostMoviePath -Destination $temp -Force
  $ff=Invoke-HostFfmpegTransform -Path $temp -Apply
  $exclusive=Invoke-FfmpegExclusiveRouteTransformV75048 -Path $temp -Apply
  $fresh=Invoke-PostStudiosFreshFrameHandoffV75049 -Path $temp -Apply
  $againFf=Invoke-HostFfmpegTransform -Path $temp -Apply
  $againExclusive=Invoke-FfmpegExclusiveRouteTransformV75048 -Path $temp -Apply
  $againFresh=Invoke-PostStudiosFreshFrameHandoffV75049 -Path $temp -Apply
  if($againFf.Changed -ne 0 -or $againExclusive.Changed -ne 0 -or $againFresh.Changed -ne 0){throw "$script:Tag composite HostMovieBridge transform is not idempotent"}
  Write-Tag "HOST STRUCTURAL_COMPAT sha=$(Get-Sha $hostMoviePath) ffmpeg_changes=$($ff.Changed) exclusive_route_changes=$($exclusive.Changed) post_studios_fresh_changes=$($fresh.Changed) old_rad_force_marker_present=$forceMarker"
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
Write-Tag "PRECHECK PASSED ffmpeg_files_ready=$ready ffmpeg_files_applied=$applied local_fork_preserved=True native_rad_backend=ffmpeg-core-inprocess ui_binks=ffmpeg post_studios_handoff=fresh-guest-frame external_rad_normal_route=False nihav_normal_route=False"
