. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
$checks=@(
  @{P='src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs';M='CapabilityEmbeddedAudio'},
  @{P='src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs';M='InfoFlagEmbeddedAudioActive'},
  @{P='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs';M='embeddedAudioActive'},
  @{P='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs';M='open_rejected_audio_provider'},
  @{P='src\SharpEmu.Libs\Media\HostMovieBridge.cs';M='MovieMode.NativeRad'}
)
foreach($c in $checks){
  $p=Join-Path $repo $c.P
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$script:Tag missing source $($c.P)"}
  $t=[IO.File]::ReadAllText($p)
  if(-not$t.Contains($c.M)){throw "$script:Tag prerequisite missing $($c.P):$($c.M)"}
}
Write-Tag 'PRECHECK PASSED managed ABI supports native embedded-audio ownership'
Write-Tag "AdapterSHA=$(Get-Sha (Get-Adapter))"
