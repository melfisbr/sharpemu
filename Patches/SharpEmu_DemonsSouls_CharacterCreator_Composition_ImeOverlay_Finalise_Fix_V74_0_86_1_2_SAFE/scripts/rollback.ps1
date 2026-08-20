. "$PSScriptRoot\common.ps1"

$pkg=PackageRoot
$ime=ImeDialogSource
$presenter=PresenterSource
$path=Join-Path $pkg 'LAST_BACKUP.txt'

if(-not(Test-Path -LiteralPath $path)){
    Write-Host "$script:Tag [ERROR] LAST_BACKUP.txt not found." -ForegroundColor Red
    exit 1
}

$backup=(Get-Content -LiteralPath $path -Raw).Trim()
Copy-Item -LiteralPath (Join-Path $backup 'ImeDialogExports.cs') -Destination $ime -Force
Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $presenter -Force

Write-Host "$script:Tag ROLLBACK COMPLETED. Backup=$backup" -ForegroundColor Yellow
