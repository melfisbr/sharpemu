Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$manifest = Join-Path $script:PackageRoot "manifest.sha256"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "manifest.sha256 ausente" }
$bad = @()
$count = 0
foreach($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw "Linha inválida no manifest: $line" }
    $expected = $Matches[1].ToLowerInvariant()
    $rel = $Matches[2]
    $path = Join-Path $script:PackageRoot $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $bad += "MISSING $rel"; continue }
    $actual = Get-Sha256 $path
    if ($actual -ne $expected) { $bad += "HASH $rel expected=$expected actual=$actual" }
    $count++
}
if ($bad.Count -gt 0) { throw ("Manifest inválido: " + ($bad -join ' | ')) }
Get-ChildItem -LiteralPath $script:PackageRoot -Recurse -Filter "*.ps1" -File | ForEach-Object { Assert-PowerShellParses $_.FullName }

$apply = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'patch_and_run.ps1'))
foreach($required in @('Path.GetRelativePath','V76.2.4.7-CANONICAL-CONTAINMENT','manifest.sha256','Emergency rollback')) {
    if (-not $apply.Contains($required)) { throw "Contrato do BuildFix ausente: $required" }
}
Write-Tag "PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed; canonical containment guard contracts passed)."
