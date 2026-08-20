. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$hostMoviePath =
    Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$radPath =
    Find-UniqueSourceFile $repo 'RadBinkEmbeddedHostApiV724323171.cs'
$audio2Path =
    Find-UniqueSourceFile $repo 'AudioOut2Exports.cs'
$optionsPath =
    Find-UniqueSourceFile $repo 'HostOptionsSkipBridgeV6113262.cs'

$introText = Get-Content -LiteralPath $introPath -Raw
$hostText = Get-Content -LiteralPath $hostMoviePath -Raw
$radText = Get-Content -LiteralPath $radPath -Raw
$audio2Text = Get-Content -LiteralPath $audio2Path -Raw
$optionsText = Get-Content -LiteralPath $optionsPath -Raw

$checks = [ordered]@{
    V1113Installed =
        [bool]($introText -match 'SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13')
    V1113LifecycleHook =
        [bool]($hostText -match 'SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13' -and
               $hostText -match 'NotifyMovieAttachV1113')
    V1112VisualFencePreserved =
        [bool]($radText -match 'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12')
    AudioOut2SharedMute =
        [bool]($audio2Text -match 'IsStartupGuestAudioMuteActiveV116')
    OptionsSkipPreserved =
        [bool]($optionsText -match '\[OPTIONS-SKIP\]\[V1\.0\]')
}

foreach ($key in $checks.Keys) {
    Write-Step ("{0}={1}" -f $key, $checks[$key])
    if (-not $checks[$key]) {
        throw "$script:Tag PRECHECK failed: $key"
    }
}

if ($introText -match 'SHARPEMU_DEMONS_TITLE_LOOP_AUDIO_RELEASE_V1_1_14') {
    throw "$script:Tag V1.1.14 already installed."
}

Write-Step "RuntimeEvidence=logo_intro_loop host_audio_probe=False guest_audio_owner=True."
Write-Step "RuntimeEvidence=AudioOut2 was silenced during logo_intro_loop with nonzero peaks."
Write-Step "RootCause=V1.1.13 held the guest mute one movie too far."
Write-Step "Fix=hold through logo_intro only; release guest ownership at logo_intro_loop attach."
Write-Step "PRECHECK PASSED."
