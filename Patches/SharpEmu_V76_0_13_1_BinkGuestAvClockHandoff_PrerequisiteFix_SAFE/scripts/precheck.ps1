param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_13_1_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V7612Baseline $repo
    $helperState=Get-AvHelperStateV7613 $repo
    $binkState=Get-BinkStateV7613 $repo
    $presenterState=Get-PresenterStateV7613 $repo
    @(
        "Tag=$PackageTag",
        "RepositoryRoot=$repo",
        "AvHelper=$helperState",
        "BinkRuntime=$binkState",
        "Presenter=$presenterState",
        'Baseline=V76.0.12.3 semantic + exact YUV helper'
    ) | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] AvHelper=$helperState BinkRuntime=$binkState Presenter=$presenterState"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$outPath"
}catch{
    @(
        "Tag=$PackageTag",
        "RepositoryRoot=$repo",
        "Error=$($_.Exception.Message)"
    ) | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
