. "$PSScriptRoot\common.ps1"
$h=Host;$s=NL([IO.File]::ReadAllText($h));$bad=0;$o=@('[V74.0.77.2] DIAGNOSTIC START')
$checks=@(
 ,@('attract_completion_marker',$s.Contains('SHARPEMU_V74_0_77_2_DEMONS_ATTRACT_GUEST_COMPLETION'))
 ,@('attract_title_guard',$s.Contains('ShouldUseDemonSoulsAttractGuestCompletionV740772'))
 ,@('completion_takeover_enabled',$s.Contains('!v740772AttractGuestCompletionHandoff'))
 ,@('one_frame_completion_reused',$s.Contains('BinkGuestCompletionShim'))
 ,@('host_completion_wait_preserved',$s.Contains('WaitForHostPlaybackToFinish'))
 ,@('ps_studios_handoff_preserved',$s.Contains('ShouldUseRadGuestCompletionHandoffV7405610'))
 ,@('build_artifact_exists',(Test-Path (Join-Path (RepoRoot) 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe')))
)
foreach($c in $checks){$o+="$($c[0])=$($c[1])";if(-not$c[1]){$bad++}}
$o+="HostSHA256=$(Sha $h)"
$stamp=Get-Date -Format yyyyMMdd_HHmmss;$d=Join-Path (Patches) ("SharpEmu_V74_0_77_2_ATTRACT_GUEST_COMPLETION_DIAGNOSTIC_"+$stamp+'.log')
if($bad){$o+="[V74.0.77.2] DIAGNOSTIC FAILED issues=$bad"}else{$o+='[V74.0.77.2] DIAGNOSTIC PASSED.'}
$o|Set-Content $d -Encoding UTF8;$o|ForEach-Object{Write-Host $_};if($bad){exit 1}
