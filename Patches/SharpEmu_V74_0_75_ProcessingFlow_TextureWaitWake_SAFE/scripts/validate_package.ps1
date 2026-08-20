param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $packageRoot 'PACKAGE_MANIFEST_SHA256.txt'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw '[V74.0.75] Manifest ausente.' }
$checked = 0
foreach ($line in Get-Content -LiteralPath $manifestPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64}) \*(.+)$') { throw "[V74.0.75] Linha de manifest invalida: $line" }
    $expected = $matches[1].ToLowerInvariant()
    $relative = $matches[2]
    $path = Join-Path $packageRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "[V74.0.75] Arquivo do pacote ausente: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "[V74.0.75] Hash invalido: $relative esperado=$expected atual=$actual" }
    $checked++
}
$parseFailures = @()
Get-ChildItem -LiteralPath (Join-Path $packageRoot 'scripts') -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) { $parseFailures += ("{0}: {1}" -f $_.Name, $parseError.Message) }
    }
}
if ($parseFailures.Count -gt 0) { throw ("[V74.0.75] PowerShell parse failure: " + ($parseFailures -join ' | ')) }
Write-Host "[V74.0.75] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed)."
