. (Join-Path $PSScriptRoot 'common.ps1')
$manifest=Join-Path (Get-PackageRootV75043) 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "$script:Tag manifest missing"}
$bad=New-Object System.Collections.Generic.List[string]
$lines=Get-Content -LiteralPath $manifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach($line in $lines){
  if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){ $bad.Add("invalid manifest line: $line"); continue }
  $expected=$matches[1].ToUpperInvariant();$rel=$matches[2];$path=Join-Path (Get-PackageRootV75043) $rel
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){ $bad.Add("missing $rel"); continue }
  $actual=Get-Sha $path;if($actual -ne $expected){$bad.Add("sha mismatch $rel expected=$expected actual=$actual")}
}
if($bad.Count){$bad|ForEach-Object{Write-Host $_};throw "$script:Tag validation failed count=$($bad.Count)"}
$adapter=Get-AdapterPath;$machine=Get-PeMachine $adapter
if($machine -ne 0x8664){throw "$script:Tag adapter is not AMD64 machine=0x$('{0:X4}' -f $machine)"}
$bytes=[IO.File]::ReadAllBytes($adapter);$ascii=[Text.Encoding]::ASCII.GetString($bytes)
$exports=@('se_bink_abi_version','se_bink_build_capabilities','se_bink_open_utf8','se_bink_decode_bgra','se_bink_get_clock_us','se_bink_request_skip','se_bink_close','se_bink_last_error_utf8','se_bink_notify_presented')
foreach($e in $exports){if(-not$ascii.Contains($e)){throw "$script:Tag adapter export missing: $e"}}

# Local-fork preservation invariant: setup must not contain any operation that
# clones, fetches, checks out, resets, cleans or downloads source/runtime.
$setupPath=Join-Path (Get-PackageRootV75043) 'scripts\setup_ffmpegcore.ps1'
$setupText=[IO.File]::ReadAllText($setupPath)
$forbidden=@(
  'https://',
  'http://',
  'Ensure-GitRepo',
  'Get-Command git',
  "& git ",
  "'git' @(",
  'Invoke-WebRequest',
  'Invoke-RestMethod',
  'Start-BitsTransfer',
  'WebClient',
  'DownloadFile('
)
foreach($needle in $forbidden){if($setupText.Contains($needle)){throw "$script:Tag LOCAL-FORK policy violation in setup: $needle"}}
Write-Tag 'LOCAL-FORK SELFTEST PASSED git_clone=False git_fetch=False checkout=False reset=False network_download=False'

# Structural transform self-test: use the packaged baseline fixtures and require
# byte-stable final hashes before accepting this package.
$tmpRoot=Join-Path ([IO.Path]::GetTempPath()) ('SharpEmu_V75043_SelfTest_'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot -Force|Out-Null
try{
  $hostTmp=Join-Path $tmpRoot 'HostMovieBridge.cs'
  $nihavTmp=Join-Path $tmpRoot 'NihavBink2Decoder.cs'
  Copy-Item -LiteralPath (Join-Path (Get-PackageRootV75043) 'reference\baseline\HostMovieBridge.cs') -Destination $hostTmp -Force
  Copy-Item -LiteralPath (Join-Path (Get-PackageRootV75043) 'reference\baseline\NihavBink2Decoder.cs') -Destination $nihavTmp -Force
  $h=Invoke-StructuralTransform -Path $hostTmp -TransformRelative 'transforms\host_movie_bridge' -Apply
  $n=Invoke-StructuralTransform -Path $nihavTmp -TransformRelative 'transforms\nihav' -Apply
  $hostExpected='1DF2C816E16659E2AE21CFDE9ECA2BE85AD5D733BF905BCC6CF330D548ADADC0'
  $nihavExpected='68DA0EB56AE8947375C51A25ABD2CF61C6B2DD6F5B48EC82A755A50F56F5FEA2'
  if((Get-Sha $hostTmp)-ne $hostExpected){throw "$script:Tag HostMovieBridge structural selftest failed actual=$(Get-Sha $hostTmp) expected=$hostExpected"}
  if((Get-Sha $nihavTmp)-ne $nihavExpected){throw "$script:Tag Nihav structural selftest failed actual=$(Get-Sha $nihavTmp) expected=$nihavExpected"}
  Write-Tag "STRUCTURAL SELFTEST PASSED host_hunks=$($h.Hunks) nihav_hunks=$($n.Hunks)"

  # Verify that an unrelated local-fork media transform is preserved while the
  # NativeRad/Nihav ownership hunks are layered on top.
  $hybridTmp=Join-Path $tmpRoot 'HostMovieBridge_HybridRestore.cs'
  Copy-Item -LiteralPath (Join-Path (Get-PackageRootV75043) 'reference\variants\HostMovieBridge_HybridRestore.cs') -Destination $hybridTmp -Force
  $hy=Invoke-StructuralTransform -Path $hybridTmp -TransformRelative 'transforms\host_movie_bridge' -Apply
  $hyText=[IO.File]::ReadAllText($hybridTmp)
  if(-not $hyText.Contains('SHARPEMU_V74_0_118_7_6_3_13_RAD_NIHAV_HYBRID_RESTORE')){throw "$script:Tag local-fork HybridRestore marker was not preserved"}
  if(-not $hyText.Contains('SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1')){throw "$script:Tag ownership marker missing after HybridRestore merge selftest"}
  Write-Tag "LOCAL-FORK MERGE SELFTEST PASSED hybrid_marker_preserved=True applied=$($hy.Applied) semantic_already=$($hy.SemanticAlready) optional_absent=$($hy.OptionalAbsent)"

  $noFallbackTmp=Join-Path $tmpRoot 'HostMovieBridge_NoExternalFallback.cs'
  Copy-Item -LiteralPath (Join-Path (Get-PackageRootV75043) 'reference\variants\HostMovieBridge_NoExternalFallback.cs') -Destination $noFallbackTmp -Force
  $nf=Invoke-StructuralTransform -Path $noFallbackTmp -TransformRelative 'transforms\host_movie_bridge'
  if($nf.OptionalAbsent -lt 1){throw "$script:Tag h06 optional-absence selftest did not exercise the local-fork path"}
  Write-Tag "LOCAL-FORK NO-FALLBACK SELFTEST PASSED optional_absent=$($nf.OptionalAbsent) semantic_already=$($nf.SemanticAlready)"
}finally{if(Test-Path $tmpRoot){Remove-Item $tmpRoot -Recurse -Force}}

Write-Tag "VALIDATION PASSED files=$($lines.Count) machine=AMD64 sha=$(Get-Sha $adapter) exports=$($exports.Count)"
