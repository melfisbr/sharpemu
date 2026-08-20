param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
if(-not(Test-Path -LiteralPath $script:StateFile -PathType Leaf)){throw "$script:Tag LAST_BACKUP_V88_1.txt missing; nothing to rollback."}
$dir=(Read-Utf8 $script:StateFile).Trim()
if(-not(Test-Path -LiteralPath $dir -PathType Container)){throw "$script:Tag backup directory missing: $dir"}
Restore-Backup $dir
Write-Host "$script:Tag ROLLBACK PASSED. Restored 4 sources from $dir" -ForegroundColor Green
