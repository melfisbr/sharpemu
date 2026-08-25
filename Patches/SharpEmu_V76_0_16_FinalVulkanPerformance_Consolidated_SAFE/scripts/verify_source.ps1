param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
Assert-FinalInstalled $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_16_FINAL_SOURCE_VERIFY_$stamp.txt"
@(
 "Tag=$PackageTag",'Status=SOURCE_VERIFY_PASSED',"RepositoryRoot=$repo",
 'V76.0.14=Applied','V76.0.15=Applied','V76.0.16=Applied','RemainingFunctionalPackages=0'
) | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
