param([string]$PackageRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($PackageRoot)){
    $PackageRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$PackageRoot=$PackageRoot.Trim('"')
$manifest=Join-Path $PackageRoot 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'SHA256SUMS.txt missing.'}

$problems=[Collections.Generic.List[string]]::new()
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    $parts=$line -split '\s+\*?',2
    if($parts.Count-ne 2){$problems.Add("bad manifest line: $line");continue}
    $expected=$parts[0].Trim().ToUpperInvariant()
    $rel=$parts[1].Trim().Replace('/','\')
    $path=Join-Path $PackageRoot $rel
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){$problems.Add("missing: $rel");continue}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual-ne$expected){$problems.Add("hash mismatch: $rel")}
}
foreach($ps in Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1'){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$tokens,[ref]$errors)
    foreach($e in $errors){$problems.Add("PowerShell parse error $($ps.Name): $($e.Message)")}
}
if($problems.Count-gt 0){throw($problems -join '; ')}
Write-Host '[V61.24.0] PACKAGE VALIDATION PASSED (hashes + PowerShell parser).'
