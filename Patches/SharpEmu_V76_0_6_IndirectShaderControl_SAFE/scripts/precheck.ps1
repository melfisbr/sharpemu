param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
$state = Get-V7606State $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_6_PRECHECK_CONTEXT_$stamp.txt"
@(
    "Tag=$PackageTag",
    "RepositoryRoot=$repo",
    "State=$state",
    'Prerequisite=V76.0.5.1 verified',
    "TranslatorHash=$(Get-Sha256 (Join-Path $repo $TranslatorRel))",
    "EvaluatorHash=$(Get-Sha256 (Join-Path $repo $EvaluatorRel))"
) | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] RepositoryRoot=$repo"
Write-Host "[$PackageTag] State=$state"
if ($state -eq 'Partial') { throw "PRECHECK FAILED: V76.0.6 parcialmente presente; nenhum arquivo foi alterado. Contexto: $outPath" }
Write-Host "[$PackageTag] PRECHECK PASSED. Contexto: $outPath"
