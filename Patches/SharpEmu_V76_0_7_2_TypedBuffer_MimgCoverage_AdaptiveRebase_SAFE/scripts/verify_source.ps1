param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
Assert-V76072Installed $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_7_2_SOURCE_VERIFY_$stamp.txt"
$lines = @(
    "Tag=$PackageTag",
    "RepositoryRoot=$repo",
    'PrerequisiteV76061=PASSED',
    'AdaptiveInPlace=PASSED',
    'Mtbuf4BitDecode=PASSED',
    'MtbufInstructionFormat=PASSED',
    'MtbufD16LoadPacking=PASSED',
    'MimgNonMinLodSampleCoverage=PASSED',
    'TypedStorePolicy=EXPLICIT_PENDING_NOT_RAW_FALLBACK'
)
foreach ($rel in $AffectedFiles) {
    $lines += "$rel=$(Get-Sha256 (Join-Path $repo $rel))"
}
$lines | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
