. (Join-Path $PSScriptRoot 'common.ps1')
Assert-TargetPackage
Assert-PowerShellParses $TargetScript
$text = Get-Text $TargetScript
$hasMarker = $text.Contains($Marker)
$anchorMatches = [regex]::Matches($text,'(?im)^\s*Expand-Archive\s+-LiteralPath\s+\$backupZip\b')
if (-not $hasMarker -and $anchorMatches.Count -ne 1) {
    throw "Anchor Expand-Archive -LiteralPath `$backupZip deve ocorrer exatamente 1 vez; encontrado=$($anchorMatches.Count)"
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $Patches "SharpEmu_V76_2_4_2_PRECHECK_CONTEXT_$stamp.txt"
@(
    "Tag=$Tag",
    "TargetPackage=$TargetPackageDir",
    "TargetScript=$TargetScript",
    "State=$(if($hasMarker){'Applied'}else{'Ready'})",
    "ExpandBackupAnchorCount=$($anchorMatches.Count)"
) | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "$Tag Target=$TargetPackageDir State=$(if($hasMarker){'Applied'}else{'Ready'})"
Write-Host "$Tag PRECHECK PASSED. Context=$out"
