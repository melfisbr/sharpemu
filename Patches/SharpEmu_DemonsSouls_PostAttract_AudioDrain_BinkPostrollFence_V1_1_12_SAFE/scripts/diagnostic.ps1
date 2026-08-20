. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$patchesRoot = Get-PatchesRoot

$introPath =
    Find-UniqueSourceFile $repo 'BinkDemonSoulsIntroAudioV7243227.cs'
$radPath =
    Find-UniqueSourceFile $repo 'RadBinkEmbeddedHostApiV724323171.cs'
$audioPath =
    Find-UniqueSourceFile $repo 'AudioOutExports.cs'
$audio2Path =
    Find-UniqueSourceFile $repo 'AudioOut2Exports.cs'
$moviePath =
    Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$optionsPath =
    Find-UniqueSourceFile $repo 'HostOptionsSkipBridgeV6113262.cs'
$presenterPath =
    Find-UniqueSourceFile $repo 'VulkanVideoPresenter.cs'

$intro = Get-Content -LiteralPath $introPath -Raw
$rad = Get-Content -LiteralPath $radPath -Raw
$audio = Get-Content -LiteralPath $audioPath -Raw
$audio2 = Get-Content -LiteralPath $audio2Path -Raw
$movie = Get-Content -LiteralPath $moviePath -Raw
$options = Get-Content -LiteralPath $optionsPath -Raw
$presenter = Get-Content -LiteralPath $presenterPath -Raw

$checks = [ordered]@{
    PostAttractTransitionFence =
        [bool]($intro -match 'SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12')
    GuestDrain =
        [bool]($intro -match 'post_attract_guest_drain_armed' -and
               $intro -match 'post_attract_guest_drain_released')
    HostAudioBlock =
        [bool]($intro -match 'post_attract_host_audio_blocked' -and
               $intro -match 'nihav_audio=False ffmpeg_audio=False')
    AudioOutUsesDrainCapableLatch =
        [bool]($audio -match 'IsStartupGuestAudioMuteActiveV116')
    AudioOut2UsesDrainCapableLatch =
        [bool]($audio2 -match 'IsStartupGuestAudioMuteActiveV116')
    RadPostrollFence =
        [bool]($rad -match 'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12')
    RadTightRehide =
        [bool]($rad -match 'rehide_period_ms=10' -and
               $rad -match 'EnforceAttractPostrollHiddenV1112')
    RadExactAttractAudioStop =
        [bool]($rad -match 'BinkDemonSoulsIntroAudioV7243227\.StopForMovie' -and
               $rad -match 'attract_nominal_end')
    CompletionShimPreserved =
        [bool]($movie -match 'SHARPEMU_DEMONS_BINK_COMPLETION_SHIM_ADVANCE_V1_1_3')
    BlackCoverPreserved =
        [bool]($presenter -match 'SHARPEMU_DEMONS_POST_STUDIOS_BLACK_COVER_V1_1_4')
    OptionsSkipPreserved =
        [bool]($options -match '\[OPTIONS-SKIP\]\[V1\.0\]')
    AttractHeadAlignmentPreserved =
        [bool]($intro -match 'SHARPEMU_DEMONS_ATTRACT_STEM_HEAD_ALIGNMENT_V1_1_10')
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $patchesRoot (
    'SharpEmu_V1_1_12_POST_ATTRACT_FENCE_DIAGNOSTIC_' +
    $stamp +
    '.log')

$resultZip = Join-Path $patchesRoot (
    'SharpEmu_V1_1_12_POST_ATTRACT_FENCE_RESULT_' +
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

$experimentalHash =
    'F221BE19DE8F8668E2FDD33F7685073017B94B763A965C8D00D99D766D0D302C'

$experimentalPresent = $false
foreach ($candidate in @(
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'),
    (Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')
)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $hash = Get-HashSafe $candidate
        Add-DiagnosticLine "NativeDll=$candidate SHA256=$hash"
        if ($hash -eq $experimentalHash) {
            $experimentalPresent = $true
        }
    }
}

Add-DiagnosticLine "ExperimentalV7510DllPresent=$experimentalPresent"
if ($experimentalPresent) {
    throw "$script:Tag Experimental V75.1.0 NihAV wrapper DLL is still deployed; RAD may not remain selected."
}

Add-DiagnosticLine "ExpectedRuntime1=[BINK-POSTROLL][V1.1.12] fence_armed file='attract_movie.bk2' ..."
Add-DiagnosticLine "ExpectedRuntime2=[BINK-POSTROLL][V1.1.12] attract_nominal_end ... audio_stopped=True postroll_hidden=True guest_drain_armed=True"
Add-DiagnosticLine "ExpectedRuntime3=[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_armed ..."
Add-DiagnosticLine "ExpectedRuntime4=[BINK-AUDIO-OWNER][V1.1.12] post_attract_host_audio_blocked next='logo_intro.bk2' ..."
Add-DiagnosticLine "ExpectedRuntime5=[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_released ..."
Add-DiagnosticLine "ForbiddenRuntime1=visible Bink/RAD postroll logo after attract_movie"
Add-DiagnosticLine "ForbiddenRuntime2=attract WaveOut cursor continuing/restarting after attract_nominal_end"
Add-DiagnosticLine "ForbiddenRuntime3=bink2.audio_start source=nihav/ffmpeg for post-attract logo_intro/logo_intro_loop"
Add-DiagnosticLine "DecoderPolicy=RAD remains the movie decoder."
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
