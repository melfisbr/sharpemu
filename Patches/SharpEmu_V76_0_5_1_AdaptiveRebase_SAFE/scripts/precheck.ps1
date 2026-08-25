param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
$stateInfo = Get-SourceState $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_5_1_PRECHECK_CONTEXT_$stamp.txt"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Tag=$PackageTag")
$lines.Add("RepositoryRoot=$repo")
$lines.Add("PatchesRoot=$patches")
$lines.Add("State=$($stateInfo.State)")
foreach ($detail in $stateInfo.Details) { $lines.Add($detail) }
foreach ($unknown in $stateInfo.Unknown) { $lines.Add($unknown) }
Set-Content -LiteralPath $outPath -Value $lines -Encoding UTF8

Write-Host "[$PackageTag] RepositoryRoot=$repo"
Write-Host "[$PackageTag] State=$($stateInfo.State)"
foreach ($detail in $stateInfo.Details) { Write-Host "  $detail" }
if ($stateInfo.State -eq 'Divergent') {
    foreach ($unknown in $stateInfo.Unknown) { Write-Host "  $unknown" -ForegroundColor Red }
    throw "PRECHECK FAILED: o source mudou novamente desde o hash capturado em 2026-08-24 11:51 -03:00. Nenhum arquivo foi alterado. Contexto: $outPath"
}
Write-Host "[$PackageTag] PRECHECK PASSED. Contexto: $outPath"
