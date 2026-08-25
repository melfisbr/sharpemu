. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
Assert-FfmpegAbiMatch
Test-OwnershipPrerequisites $repo
$ready=0;$applied=0
foreach($b in (Get-FfmpegFixedBaselines)){
  $p=Join-Path $repo $b.Rel;if(-not(Test-Path $p)){throw "$script:Tag missing source: $($b.Rel)"};$sha=Get-Sha $p
  if($sha -eq $b.Original){$ready++;Write-Tag "READY $($b.Rel) sha=$sha"}
  elseif($sha -eq $b.Patched){$applied++;Write-Tag "ALREADY_APPLIED $($b.Rel) sha=$sha"}
  else{throw "$script:Tag DIVERGENT source=$($b.Rel) sha=$sha expected_original=$($b.Original) expected_patched=$($b.Patched)"}
}
$host=Join-Path $repo 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$preview=Invoke-HostFfmpegTransform -Path $host
Write-Tag "HOST STRUCTURAL_COMPAT sha=$($preview.Before) changes_needed=$($preview.Changed) already=$($preview.Already)"
Write-Tag "PRECHECK PASSED ffmpeg_files_ready=$ready ffmpeg_files_applied=$applied local_fork_preserved=True nihav_fallback=False git_mutation=False"
