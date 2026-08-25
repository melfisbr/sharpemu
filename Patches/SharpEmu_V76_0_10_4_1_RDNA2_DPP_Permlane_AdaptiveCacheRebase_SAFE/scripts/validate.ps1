$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$PackageRoot = Split-Path -Parent $PSScriptRoot
$Tag = 'V76.0.10.4.1-RDNA2-DPP-PERMLANE-ADAPTIVE-CACHE-REBASE'
$manifest = Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "$Tag manifest ausente" }
$lines = Get-Content -LiteralPath $manifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach ($line in $lines) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "$Tag manifest invalido: $line" }
    $expected = $matches[1]
    $rel = $matches[2]
    $path = Join-Path $PackageRoot ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Tag arquivo ausente: $rel" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "$Tag hash mismatch: $rel expected=$expected actual=$actual" }
}
foreach ($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter '*.ps1') {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) {
        throw "$Tag PowerShell parse failure: $($script.Name): $($parseErrors[0].Message)"
    }
}
$networkPattern = @('Invoke','WebRequest') -join '-'
$networkPattern2 = @('Start','BitsTransfer') -join '-'
foreach ($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File |
    Where-Object { $_.Extension -in '.ps1','.cmd' -and $_.FullName -ne $PSCommandPath }) {
    $text = [System.IO.File]::ReadAllText($script.FullName)
    if ($text.IndexOf($networkPattern,[System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $text.IndexOf($networkPattern2,[System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "$Tag package script contains network downloader: $($script.Name)"
    }
}
Write-Host "[$Tag] PACKAGE VALIDATION PASSED entries=$($lines.Count) offline=PASS powershell_parse=PASS" -ForegroundColor Green
