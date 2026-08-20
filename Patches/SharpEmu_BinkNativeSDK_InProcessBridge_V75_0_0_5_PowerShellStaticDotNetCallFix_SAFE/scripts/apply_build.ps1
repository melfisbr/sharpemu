. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$repo = Get-RepoRoot
$hostMovieSourcePath = Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$playback = Find-UniqueSourceFile $repo 'MediaFramePlayback.cs'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $repo (
    '.sharpemu-hotfix-backup\BinkNativeSdkV75_0_0_' +
    $stamp)

New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item -LiteralPath $hostMovieSourcePath -Destination (
    Join-Path $backup 'HostMovieBridge.cs') -Force
Copy-Item -LiteralPath $playback -Destination (
    Join-Path $backup 'MediaFramePlayback.cs') -Force

try {
    & (Join-Path $PSScriptRoot 'install_managed_sources_v7500.ps1') `
        -Repo $repo `
        -BackupRoot $backup

    & (Join-Path $PSScriptRoot 'patch_media_frame_playback_v7500.ps1') `
        -Path $playback

    & (Join-Path $PSScriptRoot 'patch_host_movie_bridge_v7500.ps1') `
        -Path $hostMovieSourcePath

    Write-Step "Building SharpEmu.GUI Debug win-x64..."
    Invoke-GuiBuild $repo

    & (Join-Path $PSScriptRoot 'build_native_adapter.ps1')

    Write-Step "APPLY + BUILD PASSED."
    Write-Step "Backup=$backup"
}
catch {
    Write-Warning "$script:Tag Apply/build failed; restoring V75.0.0 targets."

    Copy-Item -LiteralPath (
        Join-Path $backup 'HostMovieBridge.cs') `
        -Destination $hostMovieSourcePath -Force
    Copy-Item -LiteralPath (
        Join-Path $backup 'MediaFramePlayback.cs') `
        -Destination $playback -Force

    foreach ($fileName in @(
        'BinkNativeSdkAbiV7500.cs',
        'RadBinkNativeSdkDecoderV7500.cs'
    )) {
        $target = Join-Path $repo (
            'src\SharpEmu.Libs\Media\' + $fileName)
        $saved = Join-Path $backup $fileName

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            Copy-Item -LiteralPath $saved -Destination $target -Force
        }
        else {
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        }
    }

    try { Invoke-GuiBuild $repo } catch {}
    throw
}
