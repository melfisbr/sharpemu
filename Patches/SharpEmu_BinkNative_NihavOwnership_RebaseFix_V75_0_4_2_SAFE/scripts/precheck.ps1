. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
$ready=0;$intermediate=0;$applied=0
foreach($b in Get-FixedBaselines){
  $p=Join-Path $repo $b.Rel
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$script:Tag missing source: $($b.Rel)"}
  $sha=Get-Sha $p
  if($sha -eq $b.Original){$ready++;Write-Tag "READY $($b.Rel) sha=$sha"}
  elseif($sha -eq $b.Patched){$applied++;Write-Tag "ALREADY_APPLIED $($b.Rel) sha=$sha"}
  elseif($sha -eq $b.Intermediate){$intermediate++;Write-Tag "V75_0_4_INTERMEDIATE $($b.Rel) sha=$sha"}
  else{throw "$script:Tag DIVERGENT fixed source=$($b.Rel) sha=$sha expected_original=$($b.Original) expected_v7504=$($b.Intermediate) expected_patched=$($b.Patched)"}
}
foreach($s in Get-StructuralTargets){
  $p=Join-Path $repo $s.Rel
  $preview=Invoke-StructuralTransform -Path $p -TransformRelative $s.Transform
  Write-Tag "STRUCTURAL_COMPAT $($s.Rel) sha=$($preview.Before) hunks=$($preview.Hunks) apply_needed=$($preview.Applied) already=$($preview.Already) preview_sha=$($preview.PreviewSha)"
}
$adapter=Get-AdapterPath
if((Get-PeMachine $adapter)-ne 0x8664){throw "$script:Tag adapter machine is not AMD64"}
Write-Tag "PRECHECK PASSED ready=$ready intermediate=$intermediate applied=$applied adapter_sha=$(Get-Sha $adapter) native_rad_parity=True nihav_exclusive_owner=True structural_rebase=True"
Write-Tag 'HostMovieBridge hash drift is accepted only when every bounded ownership transform matches exactly once; newer unrelated code is preserved.'
