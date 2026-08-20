param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
if(-not(Test-Path -LiteralPath $script:StateFile)){throw "$script:Tag LAST_BACKUP.txt ausente."}
$b=(Read-Utf8 $script:StateFile).Trim();if(-not $b -or -not(Test-Path -LiteralPath $b)){throw "$script:Tag backup invalido: $b"}
Restore-Backup $b
Write-Host "$script:Tag ROLLBACK PASSED. Restored=$b" -ForegroundColor Green
