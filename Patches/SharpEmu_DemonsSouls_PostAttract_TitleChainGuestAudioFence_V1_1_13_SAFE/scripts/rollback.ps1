. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-RepoRoot
$backupRoot = Join-Path $repo '.sharpemu-hotfix-backup'

$backup = @(
    Get-ChildItem -LiteralPath $backupRoot -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like 'DemonTitleChainAudioV1_1_13_*'
    } |
    Sort-Object LastWriteTime -Descending
) | Select-Object -First 1

if ($null -eq $backup) {
    throw "$script:Tag No V1.1.13 backup found."
}

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$hostMoviePath =
    Find-UniqueSourceFile $repo 'HostMovieBridge.cs'

Copy-Item -LiteralPath (
    Join-Path $backup.FullName 'BinkDemonSoulsIntroAudioV7243227.cs') `
    -Destination $introPath -Force

Copy-Item -LiteralPath (
    Join-Path $backup.FullName 'HostMovieBridge.cs') `
    -Destination $hostMoviePath -Force

Invoke-GuiBuild $repo

Write-Step "RollbackSource=$($backup.FullName)"
Write-Step "ROLLBACK PASSED."
