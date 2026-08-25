$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $PatchesRoot "SharpEmu_V76_2_4_4_PRECHECK_CONTEXT_$stamp.txt"

try {
    $state = Assert-TargetReadyOrApplied
    $targetText = Get-Text $TargetScript
    $joinCount = ([regex]::Matches($targetText, 'Join-Path\s+\$Patches\b')).Count

    @(
        "Tag=$Tag"
        "TargetPackage=$TargetPackage"
        "TargetScript=$TargetScript"
        "TargetRunner=$TargetRunner"
        "State=$state"
        "LegacyJoinPathPatchesCount=$joinCount"
    ) | Set-Content -LiteralPath $out -Encoding UTF8

    Write-Tag "Target=$TargetPackage State=$state LegacyJoinPathPatches=$joinCount"
    Write-Tag "PRECHECK PASSED. Context=$out"
    exit 0
}
catch {
    @(
        "Tag=$Tag"
        "TargetPackage=$TargetPackage"
        "TargetScript=$TargetScript"
        "ERROR=$($_.Exception.Message)"
    ) | Set-Content -LiteralPath $out -Encoding UTF8
    throw "PRECHECK FAILED: $($_.Exception.Message) Contexto: $out"
}
