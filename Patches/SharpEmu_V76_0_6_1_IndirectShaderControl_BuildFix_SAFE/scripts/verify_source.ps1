param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
Assert-V7606Installed $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_6_1_SOURCE_VERIFY_$stamp.txt"
@(
    "Tag=$PackageTag",
    "RepositoryRoot=$repo",
    'PrerequisiteV76051=PASSED',
    'IndirectControlMarkers=PASSED',
    'ScalarEvaluatorMarkers=PASSED',
    "TranslatorHash=$(Get-Sha256 (Join-Path $repo $TranslatorRel))",
    "EvaluatorHash=$(Get-Sha256 (Join-Path $repo $EvaluatorRel))",
    "HelperHash=$(Get-Sha256 (Join-Path $repo $IndirectHelperRel))"
) | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
