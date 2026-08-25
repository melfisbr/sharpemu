param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_12_2_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V7611Baseline $repo
    $binkState=Get-BinkStateV7612 $repo
    $presenterState=Get-PresenterStateV7612 $repo
    $currentHelperHash=Get-Sha256 (Join-Path $repo $HelperRel)
    $helperState=if($currentHelperHash -eq $HelperExpectedHashV7612){'Applied'}elseif($currentHelperHash -eq ''){'ReadyCopy'}elseif($currentHelperHash -eq $HelperBrokenHashV7612_1){'ReadyNamespaceBuildFix'}else{throw "Helper divergente actual=$currentHelperHash"}
    @(
        "Tag=$PackageTag",
        "RepositoryRoot=$repo",
        "BinkRuntime=$binkState",
        "Presenter=$presenterState",
        "YuvEpochHelper=$helperState hash=$currentHelperHash"
    ) | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] BinkRuntime=$binkState Presenter=$presenterState YuvEpochHelper=$helperState"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$outPath"
}catch{
    @("Tag=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
