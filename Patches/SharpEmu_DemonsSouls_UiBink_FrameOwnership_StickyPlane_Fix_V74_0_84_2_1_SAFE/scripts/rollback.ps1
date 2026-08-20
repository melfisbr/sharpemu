. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot; $p=Presenter; $last=Join-Path $pkg 'LAST_BACKUP.txt'
if (-not (Test-Path $last)) { Write-Host '[V74.0.84.2.1][ERROR] LAST_BACKUP.txt missing.' -ForegroundColor Red; exit 1 }
$bdir=(Get-Content $last -Raw).Trim()
$src=Join-Path $bdir 'VulkanVideoPresenter.cs'
if (-not (Test-Path $src)) { Write-Host "[V74.0.84.2.1][ERROR] backup missing: $src" -ForegroundColor Red; exit 1 }
Copy-Item $src $p -Force
Write-Host "[V74.0.84.2.1] rollback restored: $src" -ForegroundColor Green
