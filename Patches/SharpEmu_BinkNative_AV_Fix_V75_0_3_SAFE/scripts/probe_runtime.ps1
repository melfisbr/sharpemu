param([string]$RuntimeDll='')
. (Join-Path $PSScriptRoot 'common.ps1')
$p=Find-Runtime $RuntimeDll
if([string]::IsNullOrWhiteSpace($p)){throw "$script:Tag no bink2w64.dll found. Supply RUN_4 ... \"C:\path\bink2w64.dll\""}
$m=Get-PeMachine $p
if($m -ne 0x8664){throw ("$script:Tag runtime is not AMD64 machine=0x{0:X4} path={1}" -f $m,$p)}
$required=@('BinkOpen','BinkClose','BinkWait','BinkDoFrame','BinkCopyToBuffer','BinkNextFrame','BinkSetSoundSystem')
$audio=@('BinkOpenXAudio29','BinkOpenXAudio28','BinkOpenXAudio2','BinkOpenXAudio27','BinkOpenWaveOut','BinkOpenDirectSound')
$e=Test-Exports $p $required $audio
if($e.Known){
  if(-not$e.RequiredOk){throw "$script:Tag runtime missing required video/audio-control export(s)"}
  if(-not$e.AnyOk){throw "$script:Tag runtime has no supported native audio backend export"}
}else{Write-Tag 'WARNING dumpbin unavailable; architecture verified but exports will be checked by adapter at runtime'}
$repo=Get-RepositoryRoot
foreach($d in Get-DeployDirs){
  New-Item -ItemType Directory -Path $d -Force|Out-Null
  $dst=Join-Path $d 'bink2w64.dll'
  if(-not[string]::Equals([IO.Path]::GetFullPath($p),[IO.Path]::GetFullPath($dst),[StringComparison]::OrdinalIgnoreCase)){Copy-Item -LiteralPath $p -Destination $dst -Force}
}
$env:SHARPEMU_BINK_RUNTIME_DLL=$p
Write-Tag "RUNTIME READY path=$p sha=$(Get-Sha $p) machine=AMD64"
