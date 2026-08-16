param(
    [string]$RepositoryRoot=(Get-Location).Path
)

. "$PSScriptRoot\common.ps1"

$root =
    Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$decoder =
    Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audio =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$bootstrap =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$hostBridge =
    Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$tool =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

foreach ($path in @(
    $decoder,
    $audio,
    $bootstrap,
    $hostBridge,
    $tool
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.29] Required file missing: $path"
    }
}

$d = Read-Normalized -Path $decoder
$a = Read-Normalized -Path $audio
$b = Read-Normalized -Path $bootstrap
$h = Read-Normalized -Path $hostBridge

foreach ($marker in @(
    "V72.4.3.2.28 DEMONS_SOULS_ATTRACT_BOOT_CONTINUATION",
    "bink2.ds_boot_attract_injected"
)) {
    if (-not $h.Contains($marker)) {
        throw "[V72.4.3.2.29] V28 host prerequisite missing: $marker"
    }
}

foreach ($marker in @(
    "V72.4.3.2.27 REFERENCE_COLOR_CALIBRATED_ROW_SPLIT",
    "path=exact633-row-split-refcal-neutral",
    "12044 * cbValue",
    "8259 * crValue"
)) {
    if (-not $d.Contains($marker)) {
        throw "[V72.4.3.2.29] Decoder prerequisite missing: $marker"
    }
}

if (-not $a.Contains("V72.4.3.2.28 ATTRACT_AUDIO_RESYNC")) {
    throw "[V72.4.3.2.29] V28 attract audio prerequisite missing."
}

if (-not $b.Contains("V72.4.3.2.28 NIHAV_HIGH_PRIORITY")) {
    throw "[V72.4.3.2.29] V28 priority prerequisite missing."
}

$expectedHash =
    "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"
$toolHash =
    (Get-FileHash -LiteralPath $tool -Algorithm SHA256).
    Hash.ToLowerInvariant()

if ($toolHash -ne $expectedHash) {
    throw (
        "[V72.4.3.2.29] Native NIHAV is not active. SHA256=" +
        $toolHash)
}

Write-Host "[V72.4.3.2.29] PRECHECK PASSED."
Write-Host (
    "[V72.4.3.2.29] Native NIHAV SHA256: " +
    $toolHash)
Write-Host (
    "[V72.4.3.2.29] V28 attract/audio chain present; " +
    "exact633 packed hot path confirmed.")
