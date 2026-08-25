$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$PackageRoot=Split-Path -Parent $PSScriptRoot
$Tag='V76.0.10.3-RDNA2-DS-SWIZZLE-B32-ADAPTIVE-REBASE'
$manifest=Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "$Tag manifest ausente" }
$lines=Get-Content -LiteralPath $manifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach($line in $lines) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "$Tag manifest invalido: $line" }
    $expected=$matches[1]; $rel=$matches[2]
    $path=Join-Path $PackageRoot ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Tag arquivo ausente: $rel" }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "$Tag hash mismatch: $rel expected=$expected actual=$actual" }
}
Write-Host "[$Tag] PACKAGE VALIDATION PASSED entries=$($lines.Count) offline=PASS" -ForegroundColor Green
