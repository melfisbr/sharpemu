. (Join-Path $PSScriptRoot 'common.ps1')
$root = Split-Path $PSScriptRoot -Parent
$manifest = Join-Path $root 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifest)) { throw 'manifest.sha256 ausente' }
$lines = @(Get-Content -LiteralPath $manifest | Where-Object { $_.Trim().Length -gt 0 })
foreach ($line in $lines) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$') { throw "Manifest inválido: $line" }
    $expected = $Matches[1].ToLowerInvariant()
    $rel = $Matches[2].Replace('/','\')
    $full = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Arquivo do manifest ausente: $rel" }
    $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Hash inválido: $rel expected=$expected actual=$actual" }
}
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File | ForEach-Object { Assert-PowerShellParses $_.FullName }
# Rejeita atribuições às variáveis automáticas mais problemáticas.
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File | ForEach-Object {
    $txt = Get-Content -LiteralPath $_.FullName -Raw
    if ($txt -match '(?im)^\s*\$(host|error|home|pid|pshome|shellid)\s*=') { throw "Atribuição a variável automática detectada: $($_.Name) -> $($Matches[1])" }
}
Write-Host "$Tag PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed)."
