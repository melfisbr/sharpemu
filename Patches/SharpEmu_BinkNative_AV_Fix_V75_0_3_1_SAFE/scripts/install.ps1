. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$src=Get-Adapter;$patches=Get-PatchesRoot;$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backups=@();$destinations=@()
foreach($d in Get-DeployDirs){
  New-Item -ItemType Directory -Path $d -Force|Out-Null
  $dst=Join-Path $d 'SharpEmu.BinkNative.dll'
  if(Test-Path -LiteralPath $dst -PathType Leaf){
    $kind=if($d -match '\\Release\\'){'Release'}else{'Debug'}
    $bk=Join-Path $patches "SharpEmu.BinkNative.before_V75_0_3_${kind}_$stamp.dll"
    Copy-Item -LiteralPath $dst -Destination $bk -Force;$backups+=$bk
  }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  if((Get-Sha $dst) -ne (Get-Sha $src)){throw "$script:Tag deploy hash mismatch $dst"}
  $destinations+=$dst
  Write-Tag "DEPLOYED=$dst"
}
$state=[ordered]@{version='V75.0.3';installed_at=(Get-Date).ToString('o');adapter_sha256=(Get-Sha $src);destinations=$destinations;backups=$backups}
$state|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
Write-Tag "INSTALL PASSED backups=$($backups.Count)"
