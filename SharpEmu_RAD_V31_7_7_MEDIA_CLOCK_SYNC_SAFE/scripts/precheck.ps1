param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$required = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs",
    "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs",
    "src\SharpEmu.Libs\SharpEmu.Libs.csproj",
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
)
foreach ($rel in $required) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.7] Required file missing: $path"
    }
}

$bridge = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs")
$rad = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs")
$audio = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs")
$assist = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs")

foreach ($marker in @(
    "RadBinkExternalPlaybackV7243231.TryStart",
    "Bink RAD bridge attached:"
)) {
    if (-not $bridge.Contains($marker)) {
        throw "[V72.4.3.2.31.7.7] RAD HostMovieBridge prerequisite missing: '$marker'."
    }
}

if (-not $rad.Contains("V72.4.3.2.31.7.6") -and
    -not $rad.Contains("V72.4.3.2.31.7.7")) {
    throw "[V72.4.3.2.31.7.7] RAD prerequisite is neither V31.7.6 nor V31.7.7. Apply V31.7.6 first."
}
foreach ($marker in @(
    "bink2.rad_guest_hard_gate_started",
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStarted(moviePath)",
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStopped(moviePath)"
)) {
    if (-not $rad.Contains($marker)) {
        throw "[V72.4.3.2.31.7.7] V31.7.6 hard-gate behavior prerequisite missing: '$marker'."
    }
}

foreach ($marker in @(
    "V72.4.3.2.31.7.6: an explicitly active host decoder always owns",
    "HostMovieExecutionGateV7243214.Begin()",
    "HostMovieExecutionGateV7243214.End()"
)) {
    if (-not $assist.Contains($marker)) {
        throw "[V72.4.3.2.31.7.7] V31.7.6 hard-gate source prerequisite missing: '$marker'."
    }
}

foreach ($marker in @(
    "public static AttachDisposition PrepareAttach",
    "public static bool NotifyPresentationStarted",
    "public static void StopForMovie"
)) {
    if (-not $audio.Contains($marker)) {
        throw "[V72.4.3.2.31.7.7] Intro-audio prerequisite missing: '$marker'."
    }
}

$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.7.7] RAD REQUIRED: radvideo64.exe not found."
}
$radInfo = Get-Item -LiteralPath $radPath
$radVersion = $radInfo.VersionInfo.FileVersion
$radHash = (Get-FileHash -LiteralPath $radPath -Algorithm SHA256).Hash

Write-Host "[V72.4.3.2.31.7.7] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.31.7.7] RAD_PLAYER=" + $radPath)
Write-Host ("[V72.4.3.2.31.7.7] RAD_VERSION=" + $radVersion)
Write-Host ("[V72.4.3.2.31.7.7] RAD_SHA256=" + $radHash)
Write-Host "[V72.4.3.2.31.7.7] V31_7_6_HARD_GATE=present; preserved unchanged."
Write-Host "[V72.4.3.2.31.7.7] AUDIO_SYNC_POLICY=zero extra anchor delay; attract sidecar starts at RAD playback anchor BEFORE child HWND reveal."
Write-Host "[V72.4.3.2.31.7.7] MEDIA_CLOCK=RAD playback anchor (temporary host bridge for host-injected direct boot)."
Write-Host "[V72.4.3.2.31.7.7] EBOOT_SYNC_NOTE=final architecture should consume guest movie/audio events; current direct-boot injection runs before the guest sound path owns the sequence."
