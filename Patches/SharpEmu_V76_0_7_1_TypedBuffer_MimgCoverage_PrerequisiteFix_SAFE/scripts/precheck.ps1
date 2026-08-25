param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
$state = Get-V7607State $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_7_1_PRECHECK_CONTEXT_$stamp.txt"
$lines = @(
    "Tag=$PackageTag",
    "RepositoryRoot=$repo",
    "State=$state",
    'Prerequisite=V76.0.6.1 exact helper verified'
)
foreach ($rel in $AffectedFiles) {
    $lines += "$rel=$(Get-Sha256 (Join-Path $repo $rel))"
}
$lines | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] RepositoryRoot=$repo"
Write-Host "[$PackageTag] State=$state"
if ($state -eq 'Divergent') {
    throw "PRECHECK FAILED: source divergente da V76.0.6.1 e do payload V76.0.7.1. Contexto: $outPath"
}
Write-Host "[$PackageTag] PRECHECK PASSED. Contexto: $outPath"
