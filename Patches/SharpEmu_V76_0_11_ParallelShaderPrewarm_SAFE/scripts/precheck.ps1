param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $outPath=Join-Path $patches "SharpEmu_V76_0_11_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V76102Baseline $repo
    $cacheHash=Get-Sha256 (Join-Path $repo $CacheRel)
    $cacheState=if($cacheHash -eq $CacheV7611Hash){'Applied'}else{'Ready'}
    $agcState=Get-AgcParallelStateV7611 $repo
    @("Tag=$PackageTag","RepositoryRoot=$repo","CachePrewarm=$cacheState hash=$cacheHash","ParallelStages=$agcState") | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] CachePrewarm=$cacheState ParallelStages=$agcState"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$outPath"
}catch{
    @("Tag=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
