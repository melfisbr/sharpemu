param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Tag='[V74.0.87.2]'
$PackageRoot=$PackageRoot.Trim().Trim([char]34).Trim([char]39)
$root=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$manifest=Join-Path $root 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "$Tag manifest.sha256 ausente."}
$lines=@(Get-Content -LiteralPath $manifest | Where-Object {$_ -and -not $_.StartsWith('#')})
$n=0
foreach($line in $lines){
    if($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$'){throw "$Tag linha de manifest invalida: $line"}
    $expected=$matches[1].ToLowerInvariant();$rel=$matches[2];$path=Join-Path $root $rel
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "$Tag arquivo ausente: $rel"}
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if($actual -ne $expected){throw "$Tag hash divergente: $rel"}
    $n++
}
$ps=@(Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1)
foreach($f in $ps){
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
    if(@($errors).Count -gt 0){throw "$Tag PowerShell parse failed: $($f.Name): $($errors[0].Message)"}
}
Write-Host "$Tag PACKAGE HASH/PARSER VALIDATION PASSED ($n hashed files; $($ps.Count) PowerShell files parsed)." -ForegroundColor Green
. (Join-Path $root 'scripts\common.ps1') -PackageRoot $root
Invoke-StructuralLocatorSelfTest
Invoke-CheckoutStructuralDryRun
Write-Host "$Tag PACKAGE VALIDATION PASSED (hash + PowerShell parse + 4-marker/two-candidate dedicated-drain regression + current-checkout read-only dry-run)." -ForegroundColor Green
