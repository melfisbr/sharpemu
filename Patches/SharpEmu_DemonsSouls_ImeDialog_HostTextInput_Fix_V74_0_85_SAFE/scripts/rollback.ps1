. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot; $src=ImeDialogSource; $last=Join-Path $pkg 'LAST_BACKUP.txt'
if(-not(Test-Path -LiteralPath $last)){ Write-Host '[V74.0.85][ERROR] LAST_BACKUP.txt missing.' -ForegroundColor Red; exit 1 }
$backup=(Get-Content -LiteralPath $last -Raw).Trim(); $old=Join-Path $backup 'ImeDialogExports.cs'
if(-not(Test-Path -LiteralPath $old)){ Write-Host "[V74.0.85][ERROR] backup source missing: $old" -ForegroundColor Red; exit 1 }
Copy-Item -LiteralPath $old -Destination $src -Force
Write-Host '[V74.0.85] ROLLBACK COMPLETED.' -ForegroundColor Green
Write-Host "RestoredSHA256=$(Sha $src)"
