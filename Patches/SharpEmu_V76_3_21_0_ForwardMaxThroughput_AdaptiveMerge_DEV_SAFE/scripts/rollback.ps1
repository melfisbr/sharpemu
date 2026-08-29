param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$last = Get-ChildItem `
    -LiteralPath $Patches `
    -Filter 'V76_3_21_0_PRE_SOURCE_*.zip' `
    -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $last) {
    Fail 'backup V76.3.21.0 nao encontrado'
}

$tmp = Join-Path $Patches `
    ('_rollback_v763210_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))

Expand-Archive `
    -LiteralPath $last.FullName `
    -DestinationPath $tmp `
    -Force

foreach ($rel in @($PresenterRel,$AgcRel,$CliRel)) {
    $src = Join-Path $tmp $rel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Fail "backup sem arquivo: $rel"
    }
    Copy-Item `
        -LiteralPath $src `
        -Destination (Join-Path $Repo $rel) `
        -Force
}

Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Host "[$Tag] ROLLBACK COMPLETED backup=$($last.FullName)"
