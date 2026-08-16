param([string]$PackageRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($PackageRoot)){$PackageRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path}
$PackageRoot=$PackageRoot.Trim('"')
$m=Join-Path $PackageRoot 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $m -PathType Leaf)){throw 'SHA256SUMS.txt missing.'}
$errs=@()
foreach($l in Get-Content -LiteralPath $m){
    if([string]::IsNullOrWhiteSpace($l)){continue}
    $x=$l -split '\s+\*?',2
    if($x.Count-ne2){$errs+="bad manifest: $l";continue}
    $p=Join-Path $PackageRoot $x[1].Trim().Replace('/','\')
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){$errs+="missing $($x[1])";continue}
    if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant()-ne$x[0].Trim().ToUpperInvariant()){$errs+="hash $($x[1])"}
}
foreach($ps in Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1'){
    $t=$null;$e=$null
    [void][Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$t,[ref]$e)
    foreach($q in $e){$errs+="$($ps.Name): $($q.Message)"}
}
if($errs.Count){throw($errs -join '; ')}
Write-Host '[V62.0.1] PACKAGE VALIDATION PASSED (hashes + PowerShell parser).'
