param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_25_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V7625Baseline $repo
    $states=@()
    foreach($spec in $PatchSpecs){$states += "$($spec.Name)=$(Get-PatchState $repo $spec)"}
    $helper=Join-Path $repo $HelperRel
    $helperState=if(Test-Path -LiteralPath $helper -PathType Leaf){if((Get-Sha256 $helper)-eq $HelperSha256){'Applied'}else{'Divergent'}}else{'ReadyCopy'}
    if($helperState -eq 'Divergent'){throw "V76.0.25 helper divergente: $HelperRel"}
    @("Tag=$PackageTag","RepositoryRoot=$repo","Helper=$helperState") + $states | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] Helper=$helperState patches=Ready/Applied/NotNeeded"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$outPath"
}catch{
    @("Tag=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
