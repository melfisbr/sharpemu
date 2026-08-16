param([string]$PackageRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($PackageRoot)){$PackageRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path}
$PackageRoot=$PackageRoot.Trim('"')
$manifest=Join-Path $PackageRoot 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'SHA256SUMS.txt missing.'}
$errors=[Collections.Generic.List[string]]::new()
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    $parts=$line -split '\s+\*?',2
    if($parts.Count-ne 2){$errors.Add("bad manifest line: $line");continue}
    $p=Join-Path $PackageRoot ($parts[1].Trim().Replace('/','\'))
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){$errors.Add("missing: $($parts[1])");continue}
    $actual=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
    if($actual -ne $parts[0].Trim()){$errors.Add("hash mismatch: $($parts[1])")}
}
foreach($ps in Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1'){
    $tokens=$null;$parse=$null
    [void][Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$tokens,[ref]$parse)
    foreach($e in $parse){$errors.Add("$($ps.Name): $($e.Message)")}
}
if($errors.Count){throw($errors -join '; ')}
Write-Host '[V61.24.0.1] PACKAGE VALIDATION PASSED (hashes + PowerShell parser).'
