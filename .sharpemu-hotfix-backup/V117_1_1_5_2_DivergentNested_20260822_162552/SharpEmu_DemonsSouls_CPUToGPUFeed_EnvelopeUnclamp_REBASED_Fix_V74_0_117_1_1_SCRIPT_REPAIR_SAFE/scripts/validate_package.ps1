param()
. (Join-Path $PSScriptRoot 'common.ps1')
$root=PackageRoot
$manifest=Join-Path $root 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)){throw "$script:Tag manifest missing"}
$count=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line.Length -lt 66){throw "$script:Tag malformed manifest line"}
    $expected=$line.Substring(0,64).ToUpperInvariant()
    $rel=$line.Substring(64).TrimStart()
    if($rel.StartsWith('*')){$rel=$rel.Substring(1)}
    $p=Join-Path $root ($rel -replace '/','\')
    if(-not(Test-Path -LiteralPath $p)){throw "$script:Tag missing package file: $rel"}
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant()
    if($actual-ne$expected){throw "$script:Tag hash mismatch: $rel"}
    $count++
}
Parse-PowerShellTree $root
Assert-OriginalLayout
Write-Tag "PACKAGE VALIDATION PASSED ($count hashed files; repair scripts parsed; original V117.1 found)."
