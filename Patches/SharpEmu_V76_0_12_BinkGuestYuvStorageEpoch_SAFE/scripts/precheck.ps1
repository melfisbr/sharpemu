param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_12_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V7611Baseline $repo
    $binkState=Get-BinkStateV7612 $repo
    $presenterState=Get-PresenterStateV7612 $repo
    $helperHash=Get-Sha256 (Join-Path $repo $HelperRel)
    $helperState=if($helperHash -eq $HelperHash){'Applied'}elseif($helperHash -eq ''){'ReadyCopy'}else{throw "Helper divergente actual=$helperHash"}
    @(
        "Tag=$PackageTag",
        "RepositoryRoot=$repo",
        "BinkRuntime=$binkState",
        "Presenter=$presenterState",
        "YuvEpochHelper=$helperState hash=$helperHash"
    ) | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] BinkRuntime=$binkState Presenter=$presenterState YuvEpochHelper=$helperState"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$outPath"
}catch{
    @("Tag=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
