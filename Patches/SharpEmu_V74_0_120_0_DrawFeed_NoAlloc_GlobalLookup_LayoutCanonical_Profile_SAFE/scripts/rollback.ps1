param()
. (Join-Path $PSScriptRoot 'common.ps1')
$patches=Get-PatchesRoot
$pointer=Join-Path $patches $script:LastBackupName
if(-not(Test-Path -LiteralPath $pointer)){throw "$script:Tag backup pointer missing"}
$backup=(Get-Content -LiteralPath $pointer -Raw).Trim()
$source=Join-Path $backup 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "$script:Tag backup source missing"}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
Copy-Item -LiteralPath $source -Destination (Get-PresenterSource) -Force
Save-State 6 'ROLLED_BACK' @{backup=$backup}
Write-Tag "ROLLBACK PASSED backup=$backup"
