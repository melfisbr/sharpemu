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
$audio2Path =
    Find-UniqueSourceFile $repo 'AudioOut2Exports.cs'

$introText = Get-Content -LiteralPath $introPath -Raw
$hostText = Get-Content -LiteralPath $hostMoviePath -Raw
$radText = Get-Content -LiteralPath $radPath -Raw
$audio2Text = Get-Content -LiteralPath $audio2Path -Raw

$checks = [ordered]@{
    V1114Installed =
        [bool]($introText -match 'SHARPEMU_DEMONS_TITLE_LOOP_AUDIO_RELEASE_V1_1_14')
    IntroDrainHold =
        [bool]($introText -match 'title_intro_guest_drain_hold')
    TitleLoopGuestRelease =
        [bool]($introText -match 'title_loop_guest_audio_release' -and
               $introText -match 'guest_audio_release_requested=True')
    V1113HostLifecycleHookPreserved =
        [bool]($hostText -match 'SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13')
    V1112VisualFencePreserved =
        [bool]($radText -match 'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12')
    AudioOut2SharedMutePreserved =
        [bool]($audio2Text -match 'IsStartupGuestAudioMuteActiveV116')
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $patchesRoot (
    'SharpEmu_V1_1_14_TITLE_LOOP_AUDIO_DIAGNOSTIC_' +
    $stamp +
    '.log')

$resultZip = Join-Path $patchesRoot (
    'SharpEmu_V1_1_14_TITLE_LOOP_AUDIO_RESULT_' +
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

Add-DiagnosticLine "ExpectedRuntime1=[BINK-AUDIO-OWNER][V1.1.14] title_intro_guest_drain_hold file='logo_intro.bk2' ..."
Add-DiagnosticLine "ExpectedRuntime2=[BINK-AUDIO-OWNER][V1.1.14] title_loop_guest_audio_release file='logo_intro_loop.bk2' ... guest_audio_release_requested=True"
Add-DiagnosticLine "ExpectedRuntime3=after title_loop_guest_audio_release, recurring AudioOut2 samples must no longer be host_submit=False solely because of the V1.1.13 title-chain latch."
Add-DiagnosticLine "ExpectedRuntime4=attract movie audio and V1.1.12 Bink postroll fence remain unchanged."
Add-DiagnosticLine "Policy=NIHAV remains video-only for logo_intro_loop; guest owns title-loop audio."
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
