param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V76_0_24_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V7624Baseline $repo
    $states=@()
    foreach($spec in $PatchSpecs){$states += "$($spec.Name)=$(Get-PatchState $repo $spec)"}
    $helperPath=Join-Path $repo $HelperRel
    $helperState=if(Test-Path -LiteralPath $helperPath -PathType Leaf){
        if((Get-Sha256 $helperPath) -eq (Get-Sha256 (Join-Path $PackageRoot $HelperPayload))){'Applied'}else{'Divergent'}
    }else{'ReadyCopy'}
    if($helperState -eq 'Divergent'){throw "Helper V76.0.24 ja existe mas diverge do payload"}
    @("Tag=$PackageTag","RepositoryRoot=$repo","Helper=$helperState") + $states |
        Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] Helper=$helperState patches=ReadyOrApplied"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$out"
}catch{
    @("Tag=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") |
        Set-Content -LiteralPath $out -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $out"
}
