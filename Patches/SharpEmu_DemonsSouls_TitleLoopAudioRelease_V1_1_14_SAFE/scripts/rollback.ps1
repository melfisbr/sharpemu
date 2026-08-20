. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-RepoRoot
$backupRoot = Join-Path $repo '.sharpemu-hotfix-backup'

$backup = @(
    Get-ChildItem -LiteralPath $backupRoot -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like 'DemonTitleLoopAudioV1_1_14_*'
    } |
    Sort-Object LastWriteTime -Descending
) | Select-Object -First 1

if ($null -eq $backup) {
    throw "$script:Tag No V1.1.14 backup found."
}

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'

Copy-Item -LiteralPath (
    Join-Path $backup.FullName 'BinkDemonSoulsIntroAudioV7243227.cs') `
    -Destination $introPath -Force

Invoke-GuiBuild $repo

Write-Step "RollbackSource=$($backup.FullName)"
Write-Step "ROLLBACK PASSED."
