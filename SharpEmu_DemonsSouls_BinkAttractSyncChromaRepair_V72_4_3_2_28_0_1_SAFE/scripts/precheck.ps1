param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$hostBridgePath = Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$decoder = Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$bootstrap = Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$chroma = Join-Path $root "src\SharpEmu.Libs\Media\BinkChromaRepairV7243227.cs"
$audio = Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$tool = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

foreach ($path in @($hostBridgePath,$decoder,$bootstrap,$chroma,$audio,$tool)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.28.0.1] Required file missing: $path"
    }
}

$h = Read-Normalized -Path $hostBridgePath
$d = Read-Normalized -Path $decoder
$b = Read-Normalized -Path $bootstrap
$c = Read-Normalized -Path $chroma
$a = Read-Normalized -Path $audio

foreach ($marker in @(
    "TryStartConfiguredBootSequence()",
    "var autoPaths = orderedBootMovieNames",
    "ps_studios_logo.bk2",
    "logo_intro.bk2"
)) {
    if (-not $h.Contains($marker)) {
        throw "[V72.4.3.2.28.0.1] Host boot prerequisite missing: $marker"
    }
}

foreach ($marker in @(
    "V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP",
    "V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR",
    "V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX"
)) {
    if (-not $d.Contains($marker)) {
        throw "[V72.4.3.2.28.0.1] V27 decoder prerequisite missing: $marker"
    }
}

if (-not $c.Contains("V72.4.3.2.27")) {
    throw "[V72.4.3.2.28.0.1] V27 chroma helper missing."
}

if (-not $a.Contains("V72.4.3.2.27")) {
    throw "[V72.4.3.2.28.0.1] V27 audio helper missing."
}

if (-not $b.Contains("V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES")) {
    throw "[V72.4.3.2.28.0.1] V27 bootstrap prerequisite missing."
}

$expectedHash = "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"
$toolHash = (Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant()

if ($toolHash -ne $expectedHash) {
    throw "[V72.4.3.2.28.0.1] Native NIHAV is not active. SHA256=$toolHash"
}

$attract = "F:\JOGOSPS5\PPSA01341\movies\attract_movie.bk2"
if (-not (Test-Path -LiteralPath $attract -PathType Leaf)) {
    throw "[V72.4.3.2.28.0.1] attract_movie.bk2 missing: $attract"
}

Write-Host "[V72.4.3.2.28.0.1] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.28.0.1] Native NIHAV SHA256: " + $toolHash)
Write-Host "[V72.4.3.2.28.0.1] V27 baseline + attract_movie detected."
