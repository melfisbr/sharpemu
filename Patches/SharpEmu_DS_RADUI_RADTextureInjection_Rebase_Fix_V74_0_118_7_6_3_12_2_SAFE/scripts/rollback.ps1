param()
. (Join-Path $PSScriptRoot 'common.ps1')
$pointer=Get-BackupPointer
if(-not(Test-Path -LiteralPath $pointer)){throw "$script:Tag backup pointer missing"}
$backupRoot=(Get-Content -LiteralPath $pointer -Raw).Trim();Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
foreach($entry in $script:Files.GetEnumerator()){$source=Join-Path $backupRoot $entry.Value.Rel;$target=Get-SourcePath $entry.Value.Rel;if(-not(Test-Path -LiteralPath $source)){throw "$script:Tag backup file missing: $source"};Copy-Item -LiteralPath $source -Destination $target -Force}
Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
Write-Tag "ROLLBACK PASSED backup=$backupRoot"
