param([string]$PackageRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$PackageRoot=$PackageRoot.Trim('"')
$manifest=Join-Path $PackageRoot 'SHA256SUMS.txt'
if (!(Test-Path -LiteralPath $manifest)) { throw 'SHA256SUMS.txt missing.' }
$problems=[Collections.Generic.List[string]]::new()
foreach($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)){continue}
    $parts=$line -split '\s+\*?',2
    if($parts.Count-ne 2){$problems.Add("bad manifest line: $line");continue}
    $path=Join-Path $PackageRoot $parts[1].Trim().Replace('/','\')
    if(!(Test-Path -LiteralPath $path)){$problems.Add("missing: $($parts[1])");continue}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -ne $parts[0].Trim().ToUpperInvariant()){
        $problems.Add("hash mismatch: $($parts[1])")
    }
}
foreach($ps in Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1'){
    $tok=$null;$errs=$null
    [void][Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$tok,[ref]$errs)
    foreach($er in $errs){$problems.Add("parse $($ps.Name): $($er.Message)")}
}
if($problems.Count){throw($problems -join '; ')}
Write-Host '[V61.23.6] PACKAGE VALIDATION PASSED (hashes + PowerShell parser).'
