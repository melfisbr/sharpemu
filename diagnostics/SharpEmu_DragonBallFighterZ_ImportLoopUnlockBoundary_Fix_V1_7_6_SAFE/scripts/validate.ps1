param()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$packageRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $packageRoot "SHA256SUMS.txt"

if (-not (Test-Path -LiteralPath $manifest)) {
    throw "SHA256SUMS.txt missing."
}

$count = 0

foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $parts = $line -split '\s{2,}', 2
    if ($parts.Count -ne 2) {
        throw "Invalid manifest line: $line"
    }

    $expected = $parts[0].Trim().ToLowerInvariant()
    $relative = $parts[1].Trim()
    $path = Join-Path $packageRoot $relative

    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing package file: $relative"
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actual -ne $expected) {
        throw "SHA256 mismatch: $relative"
    }

    $count++
}

foreach ($script in Get-ChildItem -LiteralPath (Join-Path $packageRoot "scripts") -Filter "*.ps1" -File) {
    $tokens = $null
    $errors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,
        [ref]$tokens,
        [ref]$errors)

    if (@($errors).Count -gt 0) {
        throw "PowerShell parse failure in $($script.Name): $($errors[0].Message)"
    }
}

$common = [System.IO.File]::ReadAllText((Join-Path $packageRoot "scripts\common.ps1"))

foreach ($needle in @(
    "SHARPEMU_IMPORT_LOOP_UNLOCK_BOUNDARY_V1_7_6",
    "tn3VlD0hG60",
    "2Z+PpY6CaJg",
    "EgmLo6EWgso",
    "+L98PIbGttk",
    "1jfXLRVzisc",
    "WKAXJ4XBPQ4")) {

    if (-not $common.Contains($needle)) {
        throw "Required boundary marker missing: $needle"
    }
}

Write-Host "[DBFZ-ILU-176] PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed)."
