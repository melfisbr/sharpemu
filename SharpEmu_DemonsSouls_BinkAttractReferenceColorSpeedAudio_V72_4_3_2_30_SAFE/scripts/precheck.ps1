param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$decoder =
    Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audio =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$bootstrap =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$tool =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

foreach ($path in @($decoder,$audio,$bootstrap,$tool)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.30] Required file missing: $path"
    }
}

$d = Read-Normalized -Path $decoder
$a = Read-Normalized -Path $audio
$b = Read-Normalized -Path $bootstrap

foreach ($marker in @(
    "V72.4.3.2.29.0.2 DIRECT_PACKED_BLOCK9_CHROMA",
    "SampleV7243292PackedChromaBlock9(",
    "path=exact633-row-split-refcal-neutral-block9",
    "V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY",
    "TryApplyV724329DedicatedAffinity(process)",
    "V72.4.3.2.29 ATTRACT_FRAME_TRUTH_EXTENDED"
)) {
    if (-not $d.Contains($marker)) {
        throw "[V72.4.3.2.30] V29.0.2 decoder prerequisite missing: $marker"
    }
}

if (-not $a.Contains("V72.4.3.2.29 ATTRACT_DECODER_RATE_AUDIO")) {
    throw "[V72.4.3.2.30] V29 audio prerequisite missing."
}

foreach ($marker in @(
    "V72.4.3.2.29 DEDICATED_DECODER_RUNTIME_DEFAULTS",
    'SetDefault("SHARPEMU_NIHAV_DEDICATED_LOGICAL_COUNT", "2");'
)) {
    if (-not $b.Contains($marker)) {
        throw "[V72.4.3.2.30] V29 runtime prerequisite missing: $marker"
    }
}

$expectedHash =
    "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"
$toolHash =
    (Get-FileHash -LiteralPath $tool -Algorithm SHA256).
    Hash.ToLowerInvariant()

if ($toolHash -ne $expectedHash) {
    throw "[V72.4.3.2.30] Native NIHAV is not active. SHA256=$toolHash"
}

Write-Host "[V72.4.3.2.30] PRECHECK PASSED."
Write-Host "[V72.4.3.2.30] Current block9 path confirmed; it will be removed."
Write-Host "[V72.4.3.2.30] Dedicated NIHAV affinity will be preserved."
Write-Host "[V72.4.3.2.30] Attract gets reference-112 direct RGB matrix and audio tempo 0.7000."
