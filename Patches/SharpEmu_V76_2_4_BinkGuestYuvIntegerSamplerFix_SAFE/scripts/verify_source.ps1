param(
    [string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V76_2_4_SOURCE_VERIFY_$stamp.txt"
Assert-V7624Installed $repo
@(
    "Package=$PackageTag",
    "RepositoryRoot=$repo",
    'SOURCE VERIFY PASSED',
    'Guest Bink host takeover remains blocked',
    'Final Y/UV integer sampler normalized only on Bink tile-5 presentation path'
) | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $out"
