param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
$last=Get-ChildItem $Patches -Filter 'V76_3_20_3_PRE_SOURCE_*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not$last){Fail 'backup nao encontrado'}
$tmp=Join-Path $Patches ('_rollback_20_3_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
Expand-Archive $last.FullName $tmp -Force
$src=Join-Path $tmp $CliRel
if(-not(Test-Path $src)){Fail 'backup sem CLI'}
Copy-Item $src $CliPath -Force
Remove-Item $tmp -Recurse -Force
Write-Host "[$Tag] ROLLBACK COMPLETED backup=$($last.FullName)"
