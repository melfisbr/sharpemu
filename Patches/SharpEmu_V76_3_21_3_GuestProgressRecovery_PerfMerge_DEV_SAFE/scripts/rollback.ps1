param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$last = Get-ChildItem `
    -LiteralPath $Patches `
    -Filter 'V76_3_21_3_PRE_SOURCE_*.zip' `
    -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $last) {
    Fail 'backup V21.3 nao encontrado'
}

$tmp = Join-Path $Patches `
    ('_rollback_v763213_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))

Expand-Archive `
    -LiteralPath $last.FullName `
    -DestinationPath $tmp `
    -Force

$src = Join-Path $tmp $CliRel
if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    Fail 'backup sem CLI'
}

Copy-Item -LiteralPath $src -Destination $CliPath -Force
Remove-Item -LiteralPath $tmp -Recurse -Force

Write-Host "[$Tag] ROLLBACK COMPLETED backup=$($last.FullName)"
