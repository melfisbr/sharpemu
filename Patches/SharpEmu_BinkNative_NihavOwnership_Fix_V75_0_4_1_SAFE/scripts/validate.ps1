. (Join-Path $PSScriptRoot 'common.ps1')
$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "$script:Tag manifest missing"}
$bad=New-Object System.Collections.Generic.List[string]
$lines=Get-Content -LiteralPath $manifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach($line in $lines){
  if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){ $bad.Add("invalid manifest line: $line"); continue }
  $expected=$matches[1].ToUpperInvariant();$rel=$matches[2];$path=Join-Path $script:PackageRoot $rel
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){ $bad.Add("missing $rel"); continue }
  $actual=Get-Sha $path;if($actual -ne $expected){$bad.Add("sha mismatch $rel expected=$expected actual=$actual")}
}
if($bad.Count){$bad|ForEach-Object{Write-Host $_};throw "$script:Tag validation failed count=$($bad.Count)"}
$adapter=Get-AdapterPath;$machine=Get-PeMachine $adapter
if($machine -ne 0x8664){throw "$script:Tag adapter is not AMD64 machine=0x$('{0:X4}' -f $machine)"}
$bytes=[IO.File]::ReadAllBytes($adapter);$ascii=[Text.Encoding]::ASCII.GetString($bytes)
$exports=@('se_bink_abi_version','se_bink_build_capabilities','se_bink_open_utf8','se_bink_decode_bgra','se_bink_get_clock_us','se_bink_request_skip','se_bink_close','se_bink_last_error_utf8','se_bink_notify_presented')
foreach($e in $exports){if(-not$ascii.Contains($e)){throw "$script:Tag adapter export missing: $e"}}
Write-Tag "VALIDATION PASSED files=$($lines.Count) machine=AMD64 sha=$(Get-Sha $adapter) exports=$($exports.Count)"
