. "$PSScriptRoot\common.ps1"
$p=Paths
$pkg=PackageRoot
$last=Join-Path $pkg 'LAST_BACKUP.txt'
if(-not(Test-Path -LiteralPath $last)){
    Write-Host "$script:Tag [ERROR] LAST_BACKUP.txt not found." -ForegroundColor Red
    exit 1
}
$backup=(Get-Content -LiteralPath $last -Raw).Trim()
Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $p.Presenter -Force
Write-Host "$script:Tag ROLLBACK COMPLETED. Backup=$backup" -ForegroundColor Yellow
