param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
$dir = Get-ChildItem -LiteralPath $Patches -Directory -Filter 'V76_3_21_3_1_1_2_PRE_SOURCE_*' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $dir) { Fail 'backup V76.3.21.3.1.1.2 nao encontrado' }
$src = Join-Path $dir.FullName $PresenterRel
if (-not (Test-Path -LiteralPath $src)) { Fail "Presenter nao encontrado no backup: $src" }
Copy-Item -LiteralPath $src -Destination $PresenterPath -Force
Write-Host "[$Tag] ROLLBACK COMPLETED from=$($dir.FullName)"
