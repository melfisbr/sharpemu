. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$patchesRoot = Get-PatchesRoot

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
    V1113TitleChainLatch =
        [bool]($introText -match 'SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13')
    V1113LifecycleMethod =
        [bool]($introText -match 'NotifyMovieAttachV1113' -and
               $introText -match 'title_chain_guest_mute_hold')
    V1113HostHook =
        [bool]($hostMovieText -match 'SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13' -and
               $hostMovieText -match 'NotifyMovieAttachV1113')
    AudioOutStillConsultsSharedMute =
        [bool]($audioText -match 'IsStartupGuestAudioMuteActiveV116')
    AudioOut2StillConsultsSharedMute =
        [bool]($audio2Text -match 'IsStartupGuestAudioMuteActiveV116')
    V1112VisualPostrollPreserved =
        [bool]($radText -match 'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12' -and
               $radText -match 'rehide_period_ms=10')
    OptionsSkipPreserved =
        [bool]($optionsText -match '\[OPTIONS-SKIP\]\[V1\.0\]')
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $patchesRoot (
    'SharpEmu_V1_1_13_TITLE_CHAIN_AUDIO_DIAGNOSTIC_' +
    $stamp +
    '.log')

$resultZip = Join-Path $patchesRoot (
    'SharpEmu_V1_1_13_TITLE_CHAIN_AUDIO_RESULT_' +
    $stamp +
    '.zip')

$lines = New-Object System.Collections.Generic.List[string]

function Add-DiagnosticLine([string]$Line) {
    $full = "$script:Tag $Line"
    $lines.Add($full)
    Write-Host $full
}

foreach ($key in $checks.Keys) {
    Add-DiagnosticLine ("{0}={1}" -f $key, $checks[$key])
    if (-not $checks[$key]) {
        throw "$script:Tag DIAGNOSTIC failed: $key"
    }
}

Add-DiagnosticLine "ExpectedRuntime1=[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_armed reason='attract-playback-ended' ..."
Add-DiagnosticLine "ExpectedRuntime2=[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_hold ... file='logo_intro.bk2' ..."
Add-DiagnosticLine "ExpectedRuntime3=[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_hold ... file='logo_intro_loop.bk2' ..."
Add-DiagnosticLine "ExpectedRuntime4=AudioOut/AudioOut2 remain silently paced while title-chain latch is active."
Add-DiagnosticLine "ExpectedRuntime5=[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_released next='<non-title-chain movie>' ..."
Add-DiagnosticLine "ForbiddenRuntime1=audible attract soundtrack during logo_intro_loop.bk2"
Add-DiagnosticLine "NIHAVPolicy=video path unchanged; host_audio_probe remains false for logo_intro_loop."
Add-DiagnosticLine "RADPolicy=attract/logo_intro RAD behavior unchanged."
Add-DiagnosticLine "DIAGNOSTIC PASSED."

[IO.File]::WriteAllLines(
    $logPath,
    $lines,
    [Text.Encoding]::UTF8)

if (Test-Path -LiteralPath $resultZip -PathType Leaf) {
    Remove-Item -LiteralPath $resultZip -Force
}

Compress-Archive -LiteralPath @(
    $logPath
) -DestinationPath $resultZip -Force

Write-Step "DiagnosticLog=$logPath"
Write-Step "ResultZip=$resultZip"
