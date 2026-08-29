param()
. (Join-Path $PSScriptRoot 'common.ps1')

Ensure-Layout

$last = Get-ChildItem `
    -LiteralPath $Patches `
    -Filter 'V76_3_21_0_2_PRE_PRESENTER_*.cs' `
    -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $last) {
    Fail 'backup do Presenter nao encontrado'
}

Copy-Item `
    -LiteralPath $last.FullName `
    -Destination $PresenterPath `
    -Force

Write-Host (
    "[$Tag] ROLLBACK COMPLETED " +
    "presenter_sha=$(Get-HashLower $PresenterPath) " +
    "backup=$($last.FullName)"
)
