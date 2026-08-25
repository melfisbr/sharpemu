. (Join-Path $PSScriptRoot 'common.ps1')
$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)){throw "$script:Tag manifest missing"}
$bad=0;$count=0
foreach($line in Get-Content -LiteralPath $manifest){
  if([string]::IsNullOrWhiteSpace($line)){continue}
  $parts=$line -split '  ',2
  if($parts.Count -ne 2){throw "$script:Tag bad manifest line: $line"}
  $path=Join-Path $script:PackageRoot ($parts[1] -replace '/','\')
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Write-Tag "MISSING=$($parts[1])";$bad++;continue}
  $got=Get-Sha $path;$count++
  if($got -ne $parts[0].ToUpperInvariant()){Write-Tag "HASH_MISMATCH=$($parts[1])";$bad++}
}
if($bad){throw "$script:Tag validation failed bad=$bad"}
$adapter=Get-Adapter
if((Get-PeMachine $adapter) -ne 0x8664){throw "$script:Tag adapter is not AMD64"}
$exp=Test-Exports $adapter @('se_bink_abi_version','se_bink_build_capabilities','se_bink_open_utf8','se_bink_decode_bgra','se_bink_get_clock_us','se_bink_request_skip','se_bink_close','se_bink_last_error_utf8')
if($exp.Known -and -not$exp.RequiredOk){throw "$script:Tag adapter exports invalid"}
Write-Tag "VALIDATION PASSED files=$count machine=AMD64 sha=$(Get-Sha $adapter)"
