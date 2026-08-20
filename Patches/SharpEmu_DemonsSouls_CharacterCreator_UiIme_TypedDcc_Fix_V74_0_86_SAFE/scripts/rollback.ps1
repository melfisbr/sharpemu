. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot;$repo=RepoRoot;$last=Join-Path $pkg 'LAST_BACKUP.txt'
if(-not(Test-Path -LiteralPath $last)){Write-Host "$script:Tag [ERROR] LAST_BACKUP.txt not found." -ForegroundColor Red;exit 1}
$backup=(Get-Content -LiteralPath $last -Raw).Trim()
$imeOld=Join-Path $backup 'ImeDialogExports.cs';$presenterOld=Join-Path $backup 'VulkanVideoPresenter.cs'
if(-not(Test-Path -LiteralPath $imeOld) -or -not(Test-Path -LiteralPath $presenterOld)){Write-Host "$script:Tag [ERROR] backup files missing: $backup" -ForegroundColor Red;exit 1}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $imeOld -Destination (ImeDialogSource) -Force;Copy-Item -LiteralPath $presenterOld -Destination (PresenterSource) -Force
Write-Host "$script:Tag rollback restored: $backup" -ForegroundColor Green
