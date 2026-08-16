param([string]$PackageRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Parent $PSScriptRoot
}
# Defensive cleanup for cmd/native argument parsing: never let a trailing literal
# quote turn into an invalid Windows path.
$PackageRoot = $PackageRoot.Trim().Trim('"')
$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$manifest = Join-Path $PackageRoot 'SHA256SUMS.txt'
if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "SHA256SUMS.txt missing: $manifest"
}

$count = 0
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '\s+\*?', 2
    if ($parts.Count -ne 2) { throw "Invalid manifest line: $line" }
    $expected = $parts[0].ToUpperInvariant()
    $rel = $parts[1].Trim()
    $path = Join-Path $PackageRoot $rel
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing package file: $rel" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if ($actual -ne $expected) { throw "Hash mismatch: $rel" }
    $count++
}

$parseCount = 0
Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed: $($_.FullName) :: $($errors[0].Message)"
    }
    $parseCount++
}
Write-Host "[V61.23.1] PACKAGE VALIDATION PASSED ($count hashed files; $parseCount PowerShell scripts parsed)."
