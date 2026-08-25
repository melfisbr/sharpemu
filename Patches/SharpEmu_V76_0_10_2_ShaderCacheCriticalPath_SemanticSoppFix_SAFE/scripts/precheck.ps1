param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $outPath=Join-Path $patches "SharpEmu_V76_0_10_2_PRECHECK_CONTEXT_$stamp.txt"
try {
    Assert-V76093Baseline $repo
    $cacheHash=Get-Sha256 (Join-Path $repo $CacheRel)
    $cacheState=if($cacheHash -eq $CacheNewHash){'Applied'}else{'Ready'}
    $vkState=Get-VulkanSoppStateV76102 $repo
    $metalState=Get-MetalSoppStateV76102 $repo
    @("Tag=$PackageTag","RepositoryRoot=$repo","Cache=$cacheState hash=$cacheHash","VulkanSopp=$vkState","MetalSopp=$metalState") | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] Cache=$cacheState VulkanSopp=$vkState MetalSopp=$metalState"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$outPath"
} catch {
    @("Tag=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
