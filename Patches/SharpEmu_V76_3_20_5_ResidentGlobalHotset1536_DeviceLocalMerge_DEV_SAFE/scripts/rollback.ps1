param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
$last=Get-ChildItem $Patches -Filter 'V76_3_20_5_PRE_SOURCE_*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not$last){Fail 'backup V20.5 nao encontrado'}
$tmp=Join-Path $Patches ('_rollback_20_5_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
Expand-Archive $last.FullName $tmp -Force
foreach($rel in @($CliRel,$PresenterRel)){
    $src=Join-Path $tmp $rel
    if(-not(Test-Path $src)){Fail "backup sem $rel"}
    Copy-Item $src (Join-Path $Repo $rel) -Force
}
Remove-Item $tmp -Recurse -Force
Write-Host "[$Tag] ROLLBACK COMPLETED backup=$($last.FullName)"
