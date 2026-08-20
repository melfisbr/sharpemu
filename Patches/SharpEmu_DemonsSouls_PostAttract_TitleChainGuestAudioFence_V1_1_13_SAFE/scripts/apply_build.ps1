. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$repo = Get-RepoRoot
$patchesRoot = Get-PatchesRoot

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$hostMoviePath =
    Find-UniqueSourceFile $repo 'HostMovieBridge.cs'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $repo (
    '.sharpemu-hotfix-backup\DemonTitleChainAudioV1_1_13_' +
    $stamp)

$buildLog = Join-Path $patchesRoot (
    'SharpEmu_V1_1_13_TITLE_CHAIN_AUDIO_BUILD_' +
    $stamp +
    '.log')

New-Item -ItemType Directory -Force -Path $backup | Out-Null

Copy-Item -LiteralPath $introPath -Destination (
    Join-Path $backup 'BinkDemonSoulsIntroAudioV7243227.cs') -Force

Copy-Item -LiteralPath $hostMoviePath -Destination (
    Join-Path $backup 'HostMovieBridge.cs') -Force

try {
    & (Join-Path $PSScriptRoot 'patch_intro_title_chain_audio_v1113.ps1') `
        -Path $introPath

    & (Join-Path $PSScriptRoot 'patch_host_movie_title_chain_hook_v1113.ps1') `
        -Path $hostMoviePath

    $transcriptStarted = $false
    try {
        Start-Transcript -LiteralPath $buildLog -Force | Out-Null
        $transcriptStarted = $true
    }
    catch {
        Write-Step "BuildTranscriptUnavailable=$($_.Exception.GetType().Name)"
    }

    try {
        Write-Step "Building SharpEmu.GUI Debug win-x64..."
        Invoke-GuiBuild $repo
    }
    finally {
        if ($transcriptStarted) {
            try {
                Stop-Transcript | Out-Null
            }
            catch {
            }
        }
    }

    Write-Step "APPLY + BUILD PASSED."
    Write-Step "Backup=$backup"
    Write-Step "BuildLog=$buildLog"
}
catch {
    Write-Warning "$script:Tag Apply/build failed; restoring V1.1.13 targets."

    Copy-Item -LiteralPath (
        Join-Path $backup 'BinkDemonSoulsIntroAudioV7243227.cs') `
        -Destination $introPath -Force

    Copy-Item -LiteralPath (
        Join-Path $backup 'HostMovieBridge.cs') `
        -Destination $hostMoviePath -Force

    try {
        Invoke-GuiBuild $repo
    }
    catch {
    }

    throw
}
