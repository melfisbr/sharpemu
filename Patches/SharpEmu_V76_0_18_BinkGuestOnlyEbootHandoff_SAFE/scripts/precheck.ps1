param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V76_0_18_PRECHECK_CONTEXT_$stamp.txt"
try{
    Assert-V7616Baseline $repo
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add("RepositoryRoot=$repo")
    $helper=Get-HandoffHelperState $repo; $lines.Add("HandoffHelper=$helper")
    foreach($spec in $PatchSpecs){$lines.Add("$($spec.Name)=$(Get-PatchState $repo $spec)")}
    $lines | Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] HandoffHelper=$helper patches=ReadyOrApplied"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$out"
}catch{
    @("RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $out -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $out"
}
