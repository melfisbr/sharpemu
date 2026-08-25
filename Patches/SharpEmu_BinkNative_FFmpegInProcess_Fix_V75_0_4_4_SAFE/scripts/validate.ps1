. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-PackageRoot
$manifest=Join-Path $root 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "$script:Tag manifest missing"}
$bad=New-Object System.Collections.Generic.List[string]
$manifestLines=@(Get-Content -LiteralPath $manifest | Where-Object { -not[string]::IsNullOrWhiteSpace($_) })
foreach($line in $manifestLines){
  if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){$bad.Add("invalid manifest line: $line");continue}
  $expected=$matches[1].ToUpperInvariant();$rel=$matches[2];$path=Join-Path $root $rel
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){$bad.Add("missing $rel");continue}
  $actual=Get-Sha $path;if($actual -ne $expected){$bad.Add("sha mismatch $rel expected=$expected actual=$actual")}
}
if($bad.Count){$bad|ForEach-Object{Write-Host $_};throw "$script:Tag validation failed count=$($bad.Count)"}

# PowerShell 5.1 parser validation.
$parseErrors=New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.ps1'|ForEach-Object{
  $tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)|Out-Null
  foreach($e in @($errors)){$parseErrors.Add("$($_.Name):$($e.Message)")}
}
if($parseErrors.Count){$parseErrors|ForEach-Object{Write-Host $_};throw "$script:Tag PowerShell parse validation failed"}

# No command may mutate the user's Git working tree/history.
foreach($f in (Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.ps1')){
  $t=[IO.File]::ReadAllText($f.FullName)
  if($t -match '(?im)^\s*(?:&\s*)?(?:git|git\.exe)\s+(clone|fetch|pull|checkout|reset|clean|rebase|switch)\b'){throw "$script:Tag forbidden Git mutation command in $($f.Name)"}
}

foreach($b in (Get-FfmpegFixedBaselines)){$payload=Join-Path $root ('payload\'+$b.Rel);if((Get-Sha $payload) -ne $b.Patched){throw "$script:Tag payload sha mismatch: $($b.Rel)"}}
$adapter=Join-Path $root 'bin\SharpEmu.BinkNative.dll';if(-not(Test-Path $adapter)){throw "$script:Tag compatibility adapter missing"};if((Get-PeMachine $adapter)-ne 0x8664){throw "$script:Tag compatibility adapter is not AMD64"}

# Structural self-test against the exact V75.0.4.3 reference included in package.
$reference=Join-Path $root 'reference\final\HostMovieBridge.cs';if(-not(Test-Path $reference)){throw "$script:Tag HostMovieBridge reference missing"}
$temp=Join-Path $env:TEMP ("SharpEmu_V75044_HostSelfTest_"+[Guid]::NewGuid().ToString('N')+'.cs')
try{Copy-Item -LiteralPath $reference -Destination $temp -Force;$r=Invoke-HostFfmpegTransform -Path $temp -Apply;$post=[IO.File]::ReadAllText($temp);if(-not$post.Contains('SHARPEMU_BINK_FFMPEG_INPROCESS_HOST_V75_0_4_4')){throw "$script:Tag structural selftest marker missing"};if($r.Changed -lt 3){throw "$script:Tag structural selftest changed too few regions: $($r.Changed)"}}finally{if(Test-Path $temp){Remove-Item $temp -Force}}
Write-Tag "VALIDATION PASSED files=$($manifestLines.Count) ffmpeg_payloads=2 host_selftest=True machine=AMD64 git_mutation=False runtime_download=binary-only"
