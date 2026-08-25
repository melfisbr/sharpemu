. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
$ready=0;$intermediate=0;$applied=0
foreach($b in Get-Baselines){
  $p=Join-Path $repo $b.Rel
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$script:Tag missing source: $($b.Rel)"}
  $sha=Get-Sha $p
  if($sha -eq $b.Original){$ready++;Write-Tag "READY $($b.Rel) sha=$sha"}
  elseif($sha -eq $b.Patched){$applied++;Write-Tag "ALREADY_APPLIED $($b.Rel) sha=$sha"}
  elseif($sha -eq $b.Intermediate){$intermediate++;Write-Tag "V75_0_4_INTERMEDIATE $($b.Rel) sha=$sha"}
  else{throw "$script:Tag DIVERGENT source=$($b.Rel) sha=$sha expected_original=$($b.Original) expected_v7504=$($b.Intermediate) expected_patched=$($b.Patched)"}
}
$adapter=Get-AdapterPath
if((Get-PeMachine $adapter)-ne 0x8664){throw "$script:Tag adapter machine is not AMD64"}
Write-Tag "PRECHECK PASSED ready=$ready intermediate=$intermediate applied=$applied adapter_sha=$(Get-Sha $adapter) native_rad_parity=True nihav_exclusive_owner=True"
Write-Tag 'RAD parity checked: headless/no chrome, embedded A/V, first-visible audio latch, guest-live UI, main_menu loop, completion handoff, skip/close, AT9 sidecar latch, NIHAV direct-open suppression.'
