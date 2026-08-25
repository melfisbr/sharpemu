param(
    [string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V76_2_4_PRECHECK_CONTEXT_$stamp.txt"
try {
    Assert-V7618GuestOnlyBaseline $repo
    $states=@()
    foreach($spec in $PatchSpecs){$states += "$($spec.Name)=$(Get-PatchState $repo $spec)"}
    $helperState=Get-SamplerHelperState $repo
    @(
        "Package=$PackageTag",
        "RepositoryRoot=$repo",
        "SamplerHelper=$helperState",
        "PatchStates=$($states -join ';')",
        'Baseline=V76.0.18.x-hard-guest-only + V76.0.12-YUV-producer'
    ) | Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] SamplerHelper=$helperState patches=ReadyOrApplied"
    Write-Host "[$PackageTag] PRECHECK PASSED. Context=$out"
} catch {
    @("Package=$PackageTag","RepositoryRoot=$repo","Error=$($_.Exception.Message)") | Set-Content -LiteralPath $out -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $out"
}
