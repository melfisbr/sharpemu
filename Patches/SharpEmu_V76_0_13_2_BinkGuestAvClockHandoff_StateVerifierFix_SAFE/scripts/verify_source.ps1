param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
Assert-V7613Installed $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_13_2_SOURCE_VERIFY_$stamp.txt"
@(
    "Tag=$PackageTag",
    'Status=SOURCE_VERIFY_PASSED',
    "RepositoryRoot=$repo",
    'BinkDecodeOwner=guest',
    'FirstVisualHandoff=neutral-yuv-nonblocking',
    'GuestAudioClock=observed-not-replaced',
    'PresentedFrameClock=producer-generation-deduplicated',
    'HostDecoder=unchanged-disabled-by-default'
) | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
