param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_7_2_PRECHECK_CONTEXT_$stamp.txt"
try {
    $state = Get-V76072State $repo
    $lines = @(
        "Tag=$PackageTag",
        "RepositoryRoot=$repo",
        "State=$state",
        'PrerequisiteV76051=immutable-components+semantic-markers',
        'PrerequisiteV76061=exact-helper+semantic-control-flow-markers',
        'ApplyMode=adaptive-in-place; no whole-file replacement'
    )
    foreach ($rel in $AffectedFiles) {
        $lines += "$rel=$(Get-Sha256 (Join-Path $repo $rel))"
    }
    foreach ($spec in $PatchSpecs) {
        $result = Test-PatchSpec $repo $spec
        $lines += "Patch.$($spec.Name)=$($result.State)"
    }
    $lines | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "[$PackageTag] RepositoryRoot=$repo"
    Write-Host "[$PackageTag] State=$state"
    Write-Host "[$PackageTag] PRECHECK PASSED. Contexto: $outPath"
}
catch {
    @(
        "Tag=$PackageTag",
        "RepositoryRoot=$repo",
        'State=BLOCKED',
        "Reason=$($_.Exception.Message)"
    ) | Set-Content -LiteralPath $outPath -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $outPath"
}
