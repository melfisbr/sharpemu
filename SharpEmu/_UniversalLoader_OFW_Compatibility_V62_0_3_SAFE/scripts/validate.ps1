param([string]$PackageRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

$PackageRoot = $PackageRoot.Trim('"')
$manifest = Join-Path $PackageRoot 'SHA256SUMS.txt'

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw 'SHA256SUMS.txt missing.'
}

$problems = @()

foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $parts = $line -split '\s+\*?', 2
    if ($parts.Count -ne 2) {
        $problems += ('bad manifest line: {0}' -f $line)
        continue
    }

    $expected = $parts[0].Trim().ToUpperInvariant()
    $relativePath = $parts[1].Trim().Replace('/', '\')
    $path = Join-Path $PackageRoot $relativePath

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $problems += ('missing: {0}' -f $relativePath)
        continue
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        $problems += ('hash mismatch: {0}' -f $relativePath)
    }
}

$powerShellFiles = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter '*.ps1'
foreach ($powerShellFile in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $powerShellFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors)

    foreach ($parseError in $parseErrors) {
        $problems += ('PowerShell parse error {0}: {1}' -f $powerShellFile.Name, $parseError.Message)
    }
}

if ($problems.Count -gt 0) {
    throw ($problems -join '; ')
}

Write-Host ('[V62.0.3] PACKAGE VALIDATION PASSED ({0} hashed files; {1} PowerShell scripts parsed).' -f ((Get-Content -LiteralPath $manifest).Count), $powerShellFiles.Count)
