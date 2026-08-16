param([string]$PackageRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot=(Split-Path -Parent $PSScriptRoot) }
$manifest=Join-Path $PackageRoot 'SHA256SUMS.txt'
if (!(Test-Path -LiteralPath $manifest)) { throw 'SHA256SUMS.txt missing.' }
$count=0
foreach($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts=$line -split '\s+\*?',2
    if ($parts.Count -ne 2) { throw "Invalid manifest line: $line" }
    $expected=$parts[0].ToUpperInvariant(); $rel=$parts[1].Trim()
    $path=Join-Path $PackageRoot $rel
    if (!(Test-Path -LiteralPath $path)) { throw "Missing package file: $rel" }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if ($actual -ne $expected) { throw "Hash mismatch: $rel" }
    $count++
}
$parseCount=0
Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1' -File | ForEach-Object {
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell parse failed: $($_.FullName) :: $($errors[0].Message)" }
    $parseCount++
}
Write-Host "[V61.23.0] PACKAGE VALIDATION PASSED ($count hashed files; $parseCount PowerShell scripts parsed)."
