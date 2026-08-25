param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath=Join-Path $patches "SharpEmu_V76_0_16_FINAL_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V7613Baseline $repo
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add("Tag=$PackageTag")
    $lines.Add("RepositoryRoot=$repo")
    foreach($spec in $HelperSpecs){$lines.Add("Helper:$($spec.Rel)=$(Get-HelperState $repo $spec)")}
    for($i=1;$i -le 15;$i++){$lines.Add(("PresenterPatch{0:d2}={1}" -f $i,(Get-PatchPairState $repo $PresenterRel 'presenter' $i)))}
    for($i=1;$i -le 14;$i++){$lines.Add(("DetilePatch{0:d2}={1}" -f $i,(Get-PatchPairState $repo $DetileRel 'detile' $i)))}
    $lines | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$outPath"
}catch{
    @("Tag=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
