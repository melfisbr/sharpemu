. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$hostMoviePath =
    Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$radPath =
    Find-UniqueSourceFile $repo 'RadBinkEmbeddedHostApiV724323171.cs'
$audioPath =
    Find-UniqueSourceFile $repo 'AudioOutExports.cs'
$audio2Path =
    Find-UniqueSourceFile $repo 'AudioOut2Exports.cs'
$optionsPath =
    Find-UniqueSourceFile $repo 'HostOptionsSkipBridgeV6113262.cs'

$introText = Get-Content -LiteralPath $introPath -Raw
$hostMovieText = Get-Content -LiteralPath $hostMoviePath -Raw
$radText = Get-Content -LiteralPath $radPath -Raw
$audioText = Get-Content -LiteralPath $audioPath -Raw
$audio2Text = Get-Content -LiteralPath $audio2Path -Raw
$optionsText = Get-Content -LiteralPath $optionsPath -Raw

$checks = [ordered]@{
    V1112PostAttractFence =
        [bool]($introText -match 'SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12')
    V1112RadPostrollFence =
        [bool]($radText -match 'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12')
    V116AudioOutMute =
        [bool]($audioText -match 'SHARPEMU_DEMONS_STARTUP_AUDIOOUT_MUTE_V1_1_6' -and
               $audioText -match 'IsStartupGuestAudioMuteActiveV116')
    V116AudioOut2Mute =
        [bool]($audio2Text -match 'SHARPEMU_DEMONS_STARTUP_AUDIOOUT2_MUTE_V1_1_6' -and
               $audio2Text -match 'IsStartupGuestAudioMuteActiveV116')
    HostMovieAttach =
        [bool]($hostMovieText -match 'AttachMovieLocked')
    TitleLoopInternalPath =
        [bool]($hostMovieText -match 'logo_intro_loop\.bk2' -and
               $hostMovieText -match 'TITLE_LOOP_AUDIO')
    OptionsSkipPreserved =
        [bool]($optionsText -match '\[OPTIONS-SKIP\]\[V1\.0\]')
}

foreach ($key in $checks.Keys) {
    Write-Step ("{0}={1}" -f $key, $checks[$key])
    if (-not $checks[$key]) {
        throw "$script:Tag PRECHECK failed: $key"
    }
}

if ($introText -match 'SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13' -or
    $hostMovieText -match 'SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13') {
    throw "$script:Tag V1.1.13 appears already/partially installed."
}

Write-Step "ObservedRuntimeRootCause=V1.1.12 drain is elapsed-time only and releases before logo_intro_loop."
Write-Step "ObservedRuntimeTitleLoop=host_audio_probe=False guest_audio_owner=True; NIHAV is video-only in this failure."
Write-Step "FixPolicy=AudioOut/AudioOut2 remain silently paced for entire logo_intro + logo_intro_loop lifecycle."
Write-Step "RadVisualPostrollFix=preserved unchanged from V1.1.12."
Write-Step "PRECHECK PASSED."
