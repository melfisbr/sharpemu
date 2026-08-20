param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
Assert-Repo
if(-not(Test-Path -LiteralPath $script:StateFile)){throw "$script:Tag LAST_BACKUP.txt not found."}
$dir=(Read-Utf8 $script:StateFile).Trim()
if(-not $dir -or -not(Test-Path -LiteralPath $dir)){throw "$script:Tag backup directory not found: $dir"}
Restore-Backup $dir
Write-Host "$script:Tag ROLLBACK PASSED. Restored=$dir" -ForegroundColor Green
