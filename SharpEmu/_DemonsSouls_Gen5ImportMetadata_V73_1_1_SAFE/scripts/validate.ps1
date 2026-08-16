param([string]$PackageRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
$PackageRoot = $PackageRoot.Trim('"')

$manifest = Join-Path $PackageRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw '[V73.1.1] SHA256SUMS.txt missing.'
}

$problems = @()
$manifestLines = @(Get-Content -LiteralPath $manifest)

foreach ($line in $manifestLines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $parts = $line -split '\s+\*?', 2
    if ($parts.Count -ne 2) {
        $problems += ('bad manifest line: {0}' -f $line)
        continue
    }

    $expected = $parts[0].Trim().ToUpperInvariant()
    $relative = $parts[1].Trim().Replace('/', '\')
    $path = Join-Path $PackageRoot $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $problems += ('missing: {0}' -f $relative)
        continue
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        $problems += ('hash mismatch: {0}' -f $relative)
    }
}

$required = @(
    'scripts\common.ps1',
    'scripts\precheck.ps1',
    'scripts\apply_build.ps1',
    'scripts\diagnostic.ps1',
    'scripts\validate.ps1',
    'src\SharpEmu.Core\Loader\Ps5SceDynamicImportMetadata.cs',
    'evidence\EBOOT_VS_CURRENT_HLE_NAMED.csv',
    'evidence\NO_HLE_STATIC_PRIORITY.csv',
    'evidence\SELFLOADER_INTEGRATION_EVIDENCE.txt'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $relative) -PathType Leaf)) {
        $problems += ('required package file missing: {0}' -f $relative)
    }
}

$powerShellFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter '*.ps1')
foreach ($powerShellFile in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
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

Write-Host ('[V73.1.1] PACKAGE VALIDATION PASSED ({0} hashed files; {1} PowerShell scripts parsed).' -f $manifestLines.Count, $powerShellFiles.Count)
