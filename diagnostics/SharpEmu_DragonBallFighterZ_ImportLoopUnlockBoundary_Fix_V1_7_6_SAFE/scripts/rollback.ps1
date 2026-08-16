. "$PSScriptRoot\common.ps1"

$repo = Get-RepoRoot
$backupBase = Join-Path $repo ".sharpemu-hotfix-backup"

$backup = Get-ChildItem -LiteralPath $backupBase -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "DBFZ_ImportLoopUnlockBoundary_V1_7_6_*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $backup) {
    throw "No V1.7.6 backup found."
}

$imports = Join-Path $repo $Script:ImportsRelative

Copy-Item `
    -LiteralPath (Join-Path $backup.FullName "DirectExecutionBackend.Imports.cs") `
    -Destination $imports `
    -Force

Write-Host "[DBFZ-ILU-176] Rollback restored: $($backup.FullName)"
