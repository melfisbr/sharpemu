param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$dir = Get-ChildItem -LiteralPath $Patches -Directory -Filter 'V76_3_21_4_1_1_PRE_SOURCE_*' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $dir) { Fail 'backup V76.3.21.4.1.1 nao encontrado' }

$src = Join-Path $dir.FullName $AgcRel
if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    Fail "AgcExports.cs nao encontrado no backup: $src"
}

Copy-Item -LiteralPath $src -Destination $AgcPath -Force
Write-Host "[$Tag] ROLLBACK COMPLETED from=$($dir.FullName)"
