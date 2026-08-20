param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
if(-not(Test-Path -LiteralPath $script:StateFile -PathType Leaf)){throw "$script:Tag LAST_BACKUP_V87_1.txt absent."}
$dir=(Read-Utf8 $script:StateFile).Trim()
if([string]::IsNullOrWhiteSpace($dir) -or -not(Test-Path -LiteralPath $dir -PathType Container)){throw "$script:Tag invalid backup path: $dir"}
Restore-Backup $dir
Write-Host "$script:Tag ROLLBACK PASSED. Restored=$dir" -ForegroundColor Green
