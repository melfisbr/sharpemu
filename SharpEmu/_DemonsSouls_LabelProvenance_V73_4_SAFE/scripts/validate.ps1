param([string]$PackageRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
$PackageRoot = $PackageRoot.Trim('"')

$manifest = Join-Path $PackageRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw '[V73.4] SHA256SUMS.txt missing.'
}

$problems = New-Object System.Collections.Generic.List[string]
$manifestLines = @(Get-Content -LiteralPath $manifest)

foreach ($line in $manifestLines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $parts = $line -split '\s+\*?', 2
    if ($parts.Count -ne 2) {
        $problems.Add(('bad manifest line: {0}' -f $line))
        continue
    }

    $expected = $parts[0].Trim().ToUpperInvariant()
    $relative = $parts[1].Trim().Replace('/', '\')
    $path = Join-Path $PackageRoot $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $problems.Add(('missing: {0}' -f $relative))
        continue
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        $problems.Add(('hash mismatch: {0}' -f $relative))
    }
}

$psFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter '*.ps1')
foreach ($psFile in $psFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $psFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors)

    foreach ($parseError in $parseErrors) {
        $problems.Add(
            ('PowerShell parse error {0}: {1}' -f
                $psFile.Name,
                $parseError.Message))
    }
}

if ($problems.Count -gt 0) {
    throw ($problems -join '; ')
}

Write-Host (
    '[V73.4] PACKAGE VALIDATION PASSED ({0} hashed files; {1} PowerShell scripts parsed).' -f
    $manifestLines.Count,
    $psFiles.Count)
