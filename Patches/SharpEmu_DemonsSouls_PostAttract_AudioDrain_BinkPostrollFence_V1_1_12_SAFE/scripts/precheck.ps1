. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$radPath =
    Find-UniqueSourceFile $repo 'RadBinkEmbeddedHostApiV724323171.cs'
$playerPath =
    Find-UniqueSourceFile $repo 'BinkDeterministicWavePlayerV317152.cs'
$audioPath =
    Find-UniqueSourceFile $repo 'AudioOutExports.cs'
$audio2Path =
    Find-UniqueSourceFile $repo 'AudioOut2Exports.cs'
$moviePath =
    Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$presenterPath =
    Find-UniqueSourceFile $repo 'VulkanVideoPresenter.cs'
$optionsPath =
    Find-UniqueSourceFile $repo 'HostOptionsSkipBridgeV6113262.cs'

$intro = Get-Content -LiteralPath $introPath -Raw
$rad = Get-Content -LiteralPath $radPath -Raw
$player = Get-Content -LiteralPath $playerPath -Raw
$audio = Get-Content -LiteralPath $audioPath -Raw
$audio2 = Get-Content -LiteralPath $audio2Path -Raw
$movie = Get-Content -LiteralPath $moviePath -Raw
$presenter = Get-Content -LiteralPath $presenterPath -Raw
$options = Get-Content -LiteralPath $optionsPath -Raw

$checks = [ordered]@{
    V116GuestAudioLatch =
        [bool]($intro -match 'SHARPEMU_DEMONS_STARTUP_GUEST_AUDIO_OWNERSHIP_V1_1_6')
    AudioOutMuteV116 =
        [bool]($audio -match 'SHARPEMU_DEMONS_STARTUP_AUDIOOUT_MUTE_V1_1_6' -and
               $audio -match 'IsStartupGuestAudioMuteActiveV116')
    AudioOut2MuteV116 =
        [bool]($audio2 -match 'SHARPEMU_DEMONS_STARTUP_AUDIOOUT2_MUTE_V1_1_6' -and
               $audio2 -match 'IsStartupGuestAudioMuteActiveV116')
    V1110StemHeadAlignment =
        [bool]($intro -match 'SHARPEMU_DEMONS_ATTRACT_STEM_HEAD_ALIGNMENT_V1_1_10')
    V119RadRelease =
        [bool]($rad -match 'SHARPEMU_DEMONS_ATTRACT_DIRECT_RAD_WAVEOUT_RELEASE_V1_1_9')
    V119PlayerRelease =
        [bool]($player -match 'SHARPEMU_DEMONS_ATTRACT_DIRECT_RAD_WAVEOUT_RELEASE_PLAYER_V1_1_9')
    CompletionShim =
        [bool]($movie -match 'SHARPEMU_DEMONS_BINK_COMPLETION_SHIM_ADVANCE_V1_1_3')
    BlackCover =
        [bool]($presenter -match 'SHARPEMU_DEMONS_POST_STUDIOS_BLACK_COVER_V1_1_4')
    OptionsSkip =
        [bool]($options -match '\[OPTIONS-SKIP\]\[V1\.0\]')
    RadEmbeddedHost =
        [bool]($rad -match 'RadBinkEmbeddedHostApiV724323171')
    RadVisualCutoff =
        [bool]($rad -match 'CutVisualBeforePostroll')
    RadNominalEnd =
        [bool]($rad -match 'EndAtNominalMovieBoundary')
}

foreach ($key in $checks.Keys) {
    Write-Step ("{0}={1}" -f $key, $checks[$key])
    if (-not $checks[$key]) {
        throw "$script:Tag PRECHECK failed: $key"
    }
}

if ($intro -match 'SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12' -or
    $rad -match 'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12') {
    throw "$script:Tag V1.1.12 appears already/partially installed."
}

$hasV1111 =
    $intro -match 'SHARPEMU_DEMONS_POST_ATTRACT_AUDIO_OWNER_BOUNDARY_V1_1_11'
Write-Step "V1111OwnerBoundaryPresent=$([bool]$hasV1111)"
Write-Step "Compatibility=V1.1.12 works with or without V1.1.11; it supersedes the immediate guest-unmute gap."

$experimentalHash =
    'F221BE19DE8F8668E2FDD33F7685073017B94B763A965C8D00D99D766D0D302C'

foreach ($candidate in @(
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'),
    (Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')
)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $hash = Get-HashSafe $candidate
        if ($hash -eq $experimentalHash) {
            Write-Step "ExperimentalV7510DllDetected=True path=$candidate"
            Write-Step "Action=RUN_3 will back up and remove only this known experimental DLL so RAD remains selected."
        }
        else {
            Write-Step "NativeDllPresentUnknown=True path=$candidate sha256=$hash"
            Write-Step "Action=unknown native DLL will NOT be removed."
        }
    }
}

Write-Step "RootCause1=attract teardown currently releases V1.1.6 guest mute immediately; stale guest PCM can become audible."
Write-Step "RootCause2=RAD visual cutoff is one-shot; a re-shown/new RAD-owned postroll HWND can expose the Bink logo."
Write-Step "Target=RAD remains movie decoder; no NIHAV/FFmpeg audio is introduced by this package."
Write-Step "PRECHECK PASSED."
