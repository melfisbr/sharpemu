param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
if(-not(Test-Path -LiteralPath $script:StateFile)){throw "$script:Tag LAST_BACKUP.txt absent."};$b=(Read-Utf8 $script:StateFile).Trim();Restore-Backup $b;Write-Host "$script:Tag ROLLBACK PASSED. Restored=$b" -ForegroundColor Green
