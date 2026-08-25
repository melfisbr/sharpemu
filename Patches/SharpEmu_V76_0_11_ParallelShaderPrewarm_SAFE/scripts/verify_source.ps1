param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot
Assert-V7611Installed $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $outPath=Join-Path $patches "SharpEmu_V76_0_11_SOURCE_VERIFY_$stamp.txt"
@("Tag=$PackageTag",'Status=SOURCE_VERIFY_PASSED',"CacheHash=$(Get-Sha256 (Join-Path $repo $CacheRel))","ParallelHelperHash=$(Get-Sha256 (Join-Path $repo $AgcParallelRel))",'SpirvPrewarm=1','ParallelVulkanVSPS=1','CacheGenerationRetained=V76.0.10-r1')|Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
