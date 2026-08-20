. "$PSScriptRoot\common.ps1"
$manifestPath = Join-Path $script:PackageRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "$script:Tag SHA256SUMS.txt ausente." }
$lines = Get-Content -LiteralPath $manifestPath | Where-Object { $_.Trim() -ne '' }
$checked = 0
foreach ($line in $lines) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$') { throw "$script:Tag Manifest invalido: $line" }
    $expected = $matches[1].ToLowerInvariant(); $rel = $matches[2]
    $path = Join-Path $script:PackageRoot $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$script:Tag Arquivo ausente: $rel" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "$script:Tag SHA256 divergente: $rel" }
    $checked++
}
Get-ChildItem -LiteralPath $script:PackageRoot -Recurse -Filter *.ps1 | ForEach-Object { Test-PowerShellParse $_.FullName }
Write-Host "$script:Tag PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed)." -ForegroundColor Green
