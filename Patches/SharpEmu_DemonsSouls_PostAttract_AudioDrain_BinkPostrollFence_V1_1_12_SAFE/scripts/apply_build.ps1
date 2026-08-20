. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$repo = Get-RepoRoot
$patchesRoot = Get-PatchesRoot

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$radPath =
    Find-UniqueSourceFile $repo 'RadBinkEmbeddedHostApiV724323171.cs'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $repo (
    '.sharpemu-hotfix-backup\DemonPostAttractFenceV1_1_12_' +
    $stamp)

$buildLog = Join-Path $patchesRoot (
    'SharpEmu_V1_1_12_POST_ATTRACT_FENCE_BUILD_' +
    $stamp +
    '.log')

New-Item -ItemType Directory -Force -Path $backup | Out-Null

Copy-Item -LiteralPath $introPath -Destination (
    Join-Path $backup 'BinkDemonSoulsIntroAudioV7243227.cs') -Force
Copy-Item -LiteralPath $radPath -Destination (
    Join-Path $backup 'RadBinkEmbeddedHostApiV724323171.cs') -Force

$experimentalHash =
    'F221BE19DE8F8668E2FDD33F7685073017B94B763A965C8D00D99D766D0D302C'

$nativeTargets = [ordered]@{
    Debug =
        Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
    Release =
        Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
}

$removedExperimental = New-Object System.Collections.Generic.List[string]

try {
    & (Join-Path $PSScriptRoot 'patch_intro_post_attract_fence_v1112.ps1') `
        -Path $introPath

    & (Join-Path $PSScriptRoot 'patch_rad_attract_postroll_fence_v1112.ps1') `
        -Path $radPath

    foreach ($name in $nativeTargets.Keys) {
        $target = $nativeTargets[$name]

        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            continue
        }

        $hash = Get-HashSafe $target
        if ($hash -ne $experimentalHash) {
            Write-Step "NativeDllPreserved=$target sha256=$hash reason=unknown-or-nonexperimental"
            continue
        }

        $backupDll =
            Join-Path $backup (
                $name +
                '_SharpEmu.BinkNative.dll')

        Copy-Item -LiteralPath $target -Destination $backupDll -Force
        Remove-Item -LiteralPath $target -Force
        $removedExperimental.Add($name)

        Write-Step "ExperimentalV7510DllRemoved=$target"
        Write-Step "Reason=keep-RAD-player-selected"
    }

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
    Write-Warning "$script:Tag Apply/build failed; restoring V1.1.12 targets."

    Copy-Item -LiteralPath (
        Join-Path $backup 'BinkDemonSoulsIntroAudioV7243227.cs') `
        -Destination $introPath -Force

    Copy-Item -LiteralPath (
        Join-Path $backup 'RadBinkEmbeddedHostApiV724323171.cs') `
        -Destination $radPath -Force

    foreach ($name in $nativeTargets.Keys) {
        $saved =
            Join-Path $backup (
                $name +
                '_SharpEmu.BinkNative.dll')

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            $target = $nativeTargets[$name]
            New-Item -ItemType Directory -Force -Path (
                Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $saved -Destination $target -Force
        }
    }

    try {
        Invoke-GuiBuild $repo
    }
    catch {
    }

    throw
}
