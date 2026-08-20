. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot;$h=Host;$a=Assist;$p=Presenter;$last=Join-Path $pkg 'LAST_BACKUP.txt'
if(-not(Test-Path $last)){Write-Host '[V74.0.84.1][ERROR] LAST_BACKUP.txt missing.' -ForegroundColor Red;exit 1}
$bdir=(Get-Content $last -Raw).Trim();if(-not(Test-Path $bdir)){Write-Host "[V74.0.84.1][ERROR] backup missing: $bdir" -ForegroundColor Red;exit 1}
foreach($dst in @($h,$a,$p)){$src=Join-Path $bdir (Split-Path $dst -Leaf);if(-not(Test-Path $src)){throw "backup source missing: $src"};Copy-Item $src $dst -Force}
Write-Host "[V74.0.84.1] rollback restored: $bdir" -ForegroundColor Green
