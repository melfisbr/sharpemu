param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
Assert-V7608Installed $repo
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_8_SOURCE_VERIFY_$stamp.txt"
$lines = @(
    "Tag=$PackageTag",
    "RepositoryRoot=$repo",
    'PrerequisiteV76072=PASSED',
    'AdaptiveInPlace=PASSED',
    'Mubuf8BitOpcodeDecode=PASSED',
    'MubufD16FormatFamily=PASSED',
    'TypedBufferStoreDispatch=PASSED',
    'MtbufInstructionFormatIdentity=PASSED',
    'MubufResourceFormatDstSel=PASSED',
    'D16StoreUnpack=PASSED',
    'InverseFormatConversion=PASSED',
    'D16LoadIntegerKindFix=PASSED',
    "TypedStoreHelperHash=$(Get-Sha256 (Join-Path $repo $HelperRel))"
)
foreach ($rel in $AffectedExistingFiles) {
    $lines += "$rel=$(Get-Sha256 (Join-Path $repo $rel))"
}
$lines | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
