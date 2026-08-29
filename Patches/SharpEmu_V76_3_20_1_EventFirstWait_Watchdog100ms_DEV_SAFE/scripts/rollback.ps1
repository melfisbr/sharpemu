param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$last = Get-ChildItem `
    -LiteralPath $Patches `
    -Filter 'V76_3_20_1_PRE_SOURCE_*.zip' `
    -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $last) {
    Fail 'backup V76.3.20_1 nao encontrado'
}

$tmp = Join-Path $Patches ('_rollback_v76320_1_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
Expand-Archive -LiteralPath $last.FullName -DestinationPath $tmp -Force

$src = Join-Path $tmp $CliRel
if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    Fail "backup sem arquivo: $CliRel"
}
Copy-Item -LiteralPath $src -Destination $CliPath -Force

Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Host "[$Tag] ROLLBACK COMPLETED backup=$($last.FullName)"
