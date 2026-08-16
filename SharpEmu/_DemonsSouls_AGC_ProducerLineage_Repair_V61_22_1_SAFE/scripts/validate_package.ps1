. (Join-Path $PSScriptRoot "common.ps1")
$packageRoot = Get-PackageRoot
$manifest = Join-Path $packageRoot "manifest.sha256"
if (-not (Test-Path -LiteralPath $manifest)) { throw "manifest.sha256 ausente." }

$lines = Get-Content -LiteralPath $manifest
$checked = 0
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2) { throw "Linha invalida no manifest: $line" }
    $expected = $parts[0].Trim().ToUpperInvariant()
    $relative = $parts[1].Trim()
    $path = Join-Path $packageRoot ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) { throw "Arquivo ausente: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Hash divergente: $relative`nExpected=$expected`nActual=$actual"
    }
    $checked++
}
Write-Host "[V61.22.1] PACKAGE VALIDATION PASSED ($checked hashed files)." -ForegroundColor Green
