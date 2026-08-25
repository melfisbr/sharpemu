param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot; $patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $outPath=Join-Path $patches "SharpEmu_V76_0_9_PRECHECK_CONTEXT_$stamp.txt"
try {
    $state=Get-V7609State $repo
    $lines=@("Tag=$PackageTag","RepositoryRoot=$repo","State=$state",'Prerequisite=V76.0.8 semantic baseline','ApplyMode=adaptive-in-place')
    foreach ($rel in $AffectedExistingFiles) { $lines += "$rel=$(Get-Sha256 (Join-Path $repo $rel))" }
    foreach ($spec in $PatchSpecs) { $r=Test-PatchSpec $repo $spec; $lines += "Patch.$($spec.Name)=$($r.State)" }
    $lines += "Helper=$(Get-HelperState $repo)"
    $lines | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"; Write-Host "[$PackageTag] State=$state"; Write-Host "[$PackageTag] PRECHECK PASSED. Contexto: $outPath"
} catch {
    @("Tag=$PackageTag","RepositoryRoot=$repo",'State=BLOCKED',"Reason=$($_.Exception.Message)") | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
