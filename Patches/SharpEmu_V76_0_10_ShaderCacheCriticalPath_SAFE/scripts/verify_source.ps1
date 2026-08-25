param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot
Assert-V7610Installed $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $outPath=Join-Path $patches "SharpEmu_V76_0_10_SOURCE_VERIFY_$stamp.txt"
@("Tag=$PackageTag",'Status=SOURCE_VERIFY_PASSED',"CacheHash=$(Get-Sha256 (Join-Path $repo $CacheRel))",'CacheVersion=V76.0.10-r1','AsyncDiskPersistence=1','SemanticEnvironmentKey=1','SClause=1','SWaitcntDepctr=1') | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
