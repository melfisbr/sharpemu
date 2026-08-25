. (Join-Path $PSScriptRoot 'common.ps1')
Assert-TargetPackage
Assert-PowerShellParses $TargetScript
$text = Get-Text $TargetScript
$hasMarker = $text.Contains($Marker)
$anchorMatches = [regex]::Matches($text,'(?im)^\s*Expand-Archive\s+-LiteralPath\s+\$backupZip\b.*$')

# V76.2.4.3: V76.2.4.1 legitimately contains two restore sites that use the
# same $backupZip: one for manifest-entry rollback and one for RUN_1 failure
# rollback. The V76.2.4.2 materialization snippet only needs to be injected
# before the FIRST restore; once materialized, the same ZIP is valid for both.
if (-not $hasMarker -and $anchorMatches.Count -lt 1) {
    throw "Anchor de restore Expand-Archive -LiteralPath `$backupZip ausente; encontrado=$($anchorMatches.Count)"
}

$firstAnchorLine = 0
if ($anchorMatches.Count -gt 0) {
    $firstAnchorLine = 1 + ([regex]::Matches($text.Substring(0,$anchorMatches[0].Index),"`n")).Count
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $Patches "SharpEmu_V76_2_4_3_PRECHECK_CONTEXT_$stamp.txt"
@(
    "Tag=$Tag",
    "TargetPackage=$TargetPackageDir",
    "TargetScript=$TargetScript",
    "State=$(if($hasMarker){'Applied'}else{'Ready'})",
    "ExpandBackupAnchorCount=$($anchorMatches.Count)",
    "FirstExpandBackupAnchorLine=$firstAnchorLine",
    "AnchorPolicy=first-of-one-or-more"
) | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "$Tag Target=$TargetPackageDir State=$(if($hasMarker){'Applied'}else{'Ready'}) ExpandBackupAnchors=$($anchorMatches.Count) FirstAnchorLine=$firstAnchorLine"
Write-Host "$Tag PRECHECK PASSED. Context=$out"
