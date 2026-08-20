. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-RepoRoot
$backupRoot = Join-Path $repo '.sharpemu-hotfix-backup'

$backup = @(
    Get-ChildItem -LiteralPath $backupRoot -Directory `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'BinkNativeSdkV75_0_0_*'
        } |
        Sort-Object LastWriteTime -Descending
) | Select-Object -First 1

if ($null -eq $backup) {
    throw "$script:Tag No V75.0.0 backup found."
}

$hostMovieSourcePath = Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$playback = Find-UniqueSourceFile $repo 'MediaFramePlayback.cs'

Copy-Item -LiteralPath (
    Join-Path $backup.FullName 'HostMovieBridge.cs') `
    -Destination $hostMovieSourcePath -Force
Copy-Item -LiteralPath (
    Join-Path $backup.FullName 'MediaFramePlayback.cs') `
    -Destination $playback -Force

foreach ($fileName in @(
    'BinkNativeSdkAbiV7500.cs',
    'RadBinkNativeSdkDecoderV7500.cs'
)) {
    $target = Join-Path $repo (
        'src\SharpEmu.Libs\Media\' + $fileName)
    $saved = Join-Path $backup.FullName $fileName

    if (Test-Path -LiteralPath $saved -PathType Leaf) {
        Copy-Item -LiteralPath $saved -Destination $target -Force
    }
    else {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    }
}

Write-Step "Restored=$($backup.FullName)"
Write-Step "Building restored source..."
Invoke-GuiBuild $repo
Write-Step "ROLLBACK PASSED."
