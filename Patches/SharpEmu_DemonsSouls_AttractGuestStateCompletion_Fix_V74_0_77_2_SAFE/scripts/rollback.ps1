. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot;$h=Host;$f=Join-Path $pkg 'LAST_BACKUP.txt'
if(-not(Test-Path $f)){Write-Host '[V74.0.77.2][ERROR] No LAST_BACKUP.txt' -ForegroundColor Red;exit 1}
$b=(Get-Content $f -Raw).Trim();$src=Join-Path $b 'HostMovieBridge.cs'
if(-not(Test-Path $src)){Write-Host "[V74.0.77.2][ERROR] Backup missing: $src" -ForegroundColor Red;exit 1}
Copy-Item $src $h -Force;Write-Host '[V74.0.77.2] rollback restored HostMovieBridge.cs' -ForegroundColor Green
