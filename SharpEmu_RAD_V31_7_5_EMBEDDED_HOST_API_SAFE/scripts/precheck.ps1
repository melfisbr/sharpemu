param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$required = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs",
    "src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs",
    "src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs",
    "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs",
    "src\SharpEmu.Libs\SharpEmu.Libs.csproj",
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
)

foreach ($rel in $required) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.5] Required file missing: $path"
    }
}

$hostText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs")
$audioText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs")
$bootstrapText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs")
$radText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs")
$assistText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs")
$presenterText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs")
$nativeWorkerText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs")

foreach ($marker in @(
    "RAD_EXTERNAL_BACKEND",
    "MovieMode.Rad",
    "AttachRadMovieLocked",
    "Bink RAD bridge attached",
    "Bink RAD bridge completed"
)) {
    if (-not $hostText.Contains($marker)) {
        throw "[V72.4.3.2.31.7.5] RAD HostMovieBridge prerequisite missing: '$marker'."
    }
}

foreach ($marker in @(
    "BinkDemonSoulsIntroAudioV7243227",
    "pr_demons_souls_intro_music.at9",
    "pr_demons_souls_intro_sfx.at9",
    "pr_demons_souls_intro_vo.at9",
    "AttractOffsetSeconds",
    "public static bool NotifyPresentationStarted",
    "public static void StopForMovie"
)) {
    if (-not $audioText.Contains($marker)) {
        throw "[V72.4.3.2.31.7.5] V31.6 intro-audio prerequisite missing: '$marker'."
    }
}

if (-not $bootstrapText.Contains('SetDefault("SHARPEMU_BINK_MODE", "rad");')) {
    throw "[V72.4.3.2.31.7.5] RAD default is not installed in BinkRuntimeBootstrapV6113166.cs."
}

if (-not $radText.Contains("TryReadBinkAudioTrackIds") -and
    -not $radText.Contains("TryReadBinkHeaderMetadata")) {
    throw "[V72.4.3.2.31.7.5] RAD Bink header reader prerequisite missing."
}
foreach ($marker in @(
    "bink2.rad_audio_header",
    "bink2.rad_attract_audio_sidecar"
)) {
    if (-not $radText.Contains($marker)) {
        throw "[V72.4.3.2.31.7.5] V31.6 RAD source prerequisite missing: '$marker'."
    }
}


foreach ($marker in @(
    "OnMovieFrame",
    "EndMovieSession",
    "ShouldThrottleGuestGpu",
    "WaitForGuestCpuPermit"
)) {
    if (-not $assistText.Contains($marker)) {
        throw "[V72.4.3.2.31.7.5] BinkHostPlaybackAssist throttle prerequisite missing: '$marker'."
    }
}
if (-not $presenterText.Contains("BinkHostPlaybackAssist.ShouldThrottleGuestGpu")) {
    throw "[V72.4.3.2.31.7.5] V74 guest GPU cinematic backpressure hook is missing."
}
if (-not $nativeWorkerText.Contains("BinkHostPlaybackAssist.WaitForGuestCpuPermit()")) {
    throw "[V72.4.3.2.31.7.5] V72/V74 guest CPU event-park hook is missing."
}

$ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
if ($null -eq $ffmpeg) {
    $localFfmpeg = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\ffmpeg.exe"
    if (-not (Test-Path -LiteralPath $localFfmpeg -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.5] ffmpeg.exe is required to rebuild the exact 1.0000x attract audio cache."
    }
}

$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
$report = Write-RadDiscoveryReport -RepositoryRoot $root -RadPath $radPath
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.7.5] RAD REQUIRED: radvideo64.exe not found. Discovery report: $report"
}

$radItem = Get-Item -LiteralPath $radPath
$radVersion = $radItem.VersionInfo.FileVersion
$radHash = (Get-FileHash -LiteralPath $radPath -Algorithm SHA256).Hash

$binkPlay = Join-Path (Split-Path -Parent $radPath) "binkplay.exe"
$binkPlayPresent = Test-Path -LiteralPath $binkPlay -PathType Leaf

# RAD Video Tools and the licensed Bink SDK are different products.  Search for
# a real SDK runtime DLL only to report whether true same-process decoding is
# currently possible; V31.7.5 does not invent an ABI when that DLL is absent.
$sdkCandidates = @(
    (Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\bink2w64.dll"),
    (Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\bink2w64.dll"),
    (Join-Path (Split-Path -Parent $radPath) "bink2w64.dll"),
    (Join-Path (Split-Path -Parent $radPath) "binkw64.dll")
)
$sdkDll = $sdkCandidates | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and
    (Test-Path -LiteralPath $_ -PathType Leaf)
} | Select-Object -First 1

Write-Host "[V72.4.3.2.31.7.5] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.31.7.5] RAD_PLAYER=" + $radPath)
Write-Host ("[V72.4.3.2.31.7.5] RAD_VERSION=" + $radVersion)
Write-Host ("[V72.4.3.2.31.7.5] RAD_SHA256=" + $radHash)
Write-Host "[V72.4.3.2.31.7.5] INTEGRATION_MODE=SharpEmu child-window host API (strict: no independent RAD top-level window)."
Write-Host "[V72.4.3.2.31.7.5] WINDOW_DISCOVERY=PID + Process.MainWindowHandle + HWND owner; GetWindowText/GetWindowTextLength forbidden."
Write-Host ("[V72.4.3.2.31.7.5] RAD_BINKPLAY_HELPER=" + $(if ($binkPlayPresent) { $binkPlay } else { "not-found (launcher HWND path will still be tried)" }))
Write-Host "[V72.4.3.2.31.7.5] AUDIO_SYNC=attract audio starts only after verified RAD HWND embedding + playback anchor."
Write-Host "[V72.4.3.2.31.7.5] EMBEDDED_AUDIO=explicit Bink track selection (/T0...) + Windows Audio (/Z0)."
Write-Host "[V72.4.3.2.31.7.5] TRANSITION_POLICY=hide during init; visual cutoff 120 ms before corrected nominal end; kill at corrected nominal end (0 ms grace); pre-reveal HWND time is subtracted from the movie clock."
Write-Host "[V72.4.3.2.31.7.5] RESOURCE_POLICY=external RAD heartbeat activates existing BinkHostPlaybackAssist CPU event-park + guest GPU payload backpressure."
Write-Host "[V72.4.3.2.31.7.5] RESIZE_POLICY=only when SharpEmu client dimensions change; no continuous FRAMECHANGED."
Write-Host "[V72.4.3.2.31.7.5] ATTRACT_AUDIO_CACHE=full AT9 mix + exact v29 runtime tail rebuilt at native 1.0000x on apply."
if ($null -ne $sdkDll) {
    Write-Host ("[V72.4.3.2.31.7.5] BINK_SDK_RUNTIME_CANDIDATE=" + $sdkDll) -ForegroundColor Yellow
    Write-Host "[V72.4.3.2.31.7.5] NOTE: candidate is not called until an exact matching licensed SDK ABI/header is supplied."
}
else {
    Write-Host "[V72.4.3.2.31.7.5] BINK_SDK_RUNTIME_CANDIDATE=not-found"
    Write-Host "[V72.4.3.2.31.7.5] TRUE_IN_PROCESS_DECODER=False (RAD Video Tools install contains the player, not the licensed Bink SDK DLL)." -ForegroundColor Yellow
}
Write-Host ("[V72.4.3.2.31.7.5] Discovery report: " + $report)
