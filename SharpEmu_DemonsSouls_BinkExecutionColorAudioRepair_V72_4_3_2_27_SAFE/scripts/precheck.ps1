param(
    [string]$RepositoryRoot=(Get-Location).Path
)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Split-Path -Parent $PSScriptRoot

$decoder =
    Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audio =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkHostAudioBridgeV7241.cs"
$hostBridge =
    Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$bootstrap =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$tool =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$nativePayload =
    Join-Path $packageRoot "payload\nihav-tool-native.exe"

foreach ($path in @(
    $decoder,
    $audio,
    $hostBridge,
    $bootstrap,
    $tool,
    $nativePayload
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.27] Required file missing: $path"
    }
}

$d = Read-Normalized -Path $decoder
$a = Read-Normalized -Path $audio
$h = Read-Normalized -Path $hostBridge
$b = Read-Normalized -Path $bootstrap

$alreadyInstalled =
    $d.Contains("V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR") -and
    $d.Contains("V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP") -and
    $d.Contains("V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX") -and
    $a.Contains("V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO") -and
    $b.Contains("V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES")

if (-not $alreadyInstalled) {
    foreach ($marker in @(
        "V72.4.3.2.17 REFERENCE_COLOR_CALIBRATED_ROW_SPLIT",
        "V72.4.3.2.22 REFERENCE_NEUTRAL_GATE_V2",
        "V72.4.3.2.25 HYBRID_REALTIME_CATCHUP",
        "var planarU =",
        "var planarV =",
        "var yPlane = planar[..yBytes];",
        "12044 * cbValue",
        "14647 * crValue",
        "8259 * crValue"
    )) {
        if (-not $d.Contains($marker)) {
            throw "[V72.4.3.2.27] Decoder prerequisite missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.24 AUDIO_PRESENTATION_SYNC",
        "NotifyPresentationStarted(string moviePath)",
        "private static long _generation;"
    )) {
        if (-not $a.Contains($marker)) {
            throw "[V72.4.3.2.27] Audio prerequisite missing: $marker"
        }
    }

    if (-not $h.Contains("bink2.audio_presentation_sync")) {
        throw "[V72.4.3.2.27] V24 first-presented-frame audio hook is missing."
    }

    foreach ($marker in @(
        "V72.4.3.2.25 HYBRID_REALTIME_STREAMING",
        'SetDefault("SHARPEMU_NIHAV_STREAM_FULL_CACHE", "0");',
        'SetDefault("SHARPEMU_BINK_REALTIME_DEADLINE", "1");'
    )) {
        if (-not $b.Contains($marker)) {
            throw "[V72.4.3.2.27] Bootstrap prerequisite missing: $marker"
        }
    }
}

$payloadHash =
    (Get-FileHash -LiteralPath $nativePayload -Algorithm SHA256).
    Hash.ToLowerInvariant()

if ($payloadHash -ne
    "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18") {
    throw "[V72.4.3.2.27] Native NIHAV payload hash mismatch."
}

$currentToolHash =
    (Get-FileHash -LiteralPath $tool -Algorithm SHA256).
    Hash.ToLowerInvariant()

Write-Host "[V72.4.3.2.27] PRECHECK PASSED."
Write-Host (
    "[V72.4.3.2.27] V27 already installed: " +
    $alreadyInstalled)
Write-Host (
    "[V72.4.3.2.27] Current NIHAV SHA256: " +
    $currentToolHash)
Write-Host (
    "[V72.4.3.2.27] V27 native NIHAV SHA256: " +
    $payloadHash)

$game = "F:\JOGOSPS5\PPSA01341"
$assets = @(
    (Join-Path $game "movies\ps_studios_logo.bk2"),
    (Join-Path $game "movies\logo_intro.bk2"),
    (Join-Path $game "sound\streams\07_cutscene_music\pr_demons_souls_intro_music.at9"),
    (Join-Path $game "sound\streams\05_cutscene_sfx\pr_demons_souls_intro_sfx.at9"),
    (Join-Path $game "sound\streams\06_cutscene_vo\en\pr_demons_souls_intro_vo.at9")
)

$missingAssets = @(
    $assets |
    Where-Object {
        -not (Test-Path -LiteralPath $_ -PathType Leaf)
    }
)

if ($missingAssets.Count -eq 0) {
    Write-Host "[V72.4.3.2.27] Demon's Souls video/audio assets detected."
}
else {
    Write-Host (
        "[V72.4.3.2.27] NOTE: game asset precheck found " +
        $missingAssets.Count +
        " missing path(s). Source patch/build can still proceed.") `
        -ForegroundColor Yellow
}

$ffmpeg =
    Get-Command ffmpeg.exe -ErrorAction SilentlyContinue

if ($null -eq $ffmpeg) {
    $ffmpeg =
        Get-Command ffmpeg -ErrorAction SilentlyContinue
}

if ($null -eq $ffmpeg) {
    Write-Host (
        "[V72.4.3.2.27] NOTE: ffmpeg is not in PATH. " +
        "External intro AT9 mixing will require ffmpeg at runtime.") `
        -ForegroundColor Yellow
}
else {
    Write-Host (
        "[V72.4.3.2.27] ffmpeg: " +
        $ffmpeg.Source)
}
