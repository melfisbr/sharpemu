. (Join-Path $PSScriptRoot 'common.ps1')
Assert-TargetPackage
Assert-PowerShellParses $TargetScript
$text = Get-Text $TargetScript
if (-not $text.Contains($Marker)) { throw 'Fix V76.2.4.2 ausente do patch_target.ps1 alvo.' }
if ($text -notmatch '(?s)V76\.2\.4\.2-BACKUP-MATERIALIZATION.*?Compress-Archive.*?\$backupZip.*?Test-Path') {
    throw 'Contratos de materialização/verificação do backup V76.2.4.2 incompletos.'
}

$restoreAnchors = [regex]::Matches($text,'(?im)^\s*Expand-Archive\s+-LiteralPath\s+\$backupZip\b.*$')
if ($restoreAnchors.Count -lt 1) { throw 'Nenhum restore por $backupZip encontrado após o fix.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $Patches "SharpEmu_V76_2_4_3_SOURCE_VERIFY_$stamp.txt"
@(
    "TargetScript=$TargetScript",
    "Marker=$Marker",
    "PowerShellParse=PASS",
    "BackupMaterializationContract=PASS",
    "ExpandBackupAnchorCount=$($restoreAnchors.Count)",
    "AnchorPolicy=first-of-one-or-more"
) | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "$Tag VERIFY PASSED. $out"
