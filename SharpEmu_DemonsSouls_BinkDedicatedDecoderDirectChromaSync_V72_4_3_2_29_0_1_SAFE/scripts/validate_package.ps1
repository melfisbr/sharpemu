param([string]$PackageRoot="")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$candidate = $PackageRoot
if ([string]::IsNullOrWhiteSpace($candidate)) {
    $candidate = Split-Path -Parent $PSScriptRoot
}

$candidate =
    $candidate.Trim().Trim('"').TrimEnd('\','/')
$root =
    (Resolve-Path -LiteralPath $candidate).Path

$manifest = Join-Path $root "SHA256SUMS.txt"
$count = 0

foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $match =
        [regex]::Match(
            $line,
            '^([0-9a-fA-F]{64})  (.+)$')

    if (-not $match.Success) {
        throw "[V72.4.3.2.29.0.1] Invalid manifest line."
    }

    $relative = $match.Groups[2].Value
    $path =
        Join-Path $root ($relative.Replace('/','\'))

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.29.0.1] Package file missing: $relative"
    }

    $actual =
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).
        Hash.ToLowerInvariant()

    if ($actual -ne
        $match.Groups[1].Value.ToLowerInvariant()) {
        throw "[V72.4.3.2.29.0.1] Hash mismatch: $relative"
    }

    $count++
}

foreach ($ps1 in Get-ChildItem `
    -LiteralPath (Join-Path $root "scripts") `
    -Filter *.ps1 `
    -File) {

    $tokens = $null
    $errors = $null

    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,
        [ref]$tokens,
        [ref]$errors)

    if ($errors.Count -gt 0) {
        throw (
            "[V72.4.3.2.29.0.1] PowerShell parse failed: " +
            $ps1.Name +
            " :: " +
            $errors[0].Message)
    }
}

# V72.4.3.2.29.0.1 REFERENCE_MARKER_VERSION_GUARD
$precheckText =
    [IO.File]::ReadAllText(
        (Join-Path $root "scripts\precheck.ps1"))

if (-not $precheckText.Contains(
        "V72.4.3.2.17 REFERENCE_COLOR_CALIBRATED_ROW_SPLIT")) {
    throw "[V72.4.3.2.29.0.1] Correct V17 reference-color prerequisite marker is missing."
}

if ($precheckText.Contains(
        "V72.4.3.2.27 REFERENCE_COLOR_CALIBRATED_ROW_SPLIT")) {
    throw "[V72.4.3.2.29.0.1] Invalid V27 reference-color prerequisite marker regression detected."
}

$audio =
    [IO.File]::ReadAllText(
        (Join-Path $root "payload\BinkDemonSoulsIntroAudioV7243227.cs"))
$affinity =
    [IO.File]::ReadAllText(
        (Join-Path $root "payload\dedicated_affinity_helper.cs.txt"))
$chroma =
    [IO.File]::ReadAllText(
        (Join-Path $root "payload\exact633_chroma.new.txt"))

foreach ($marker in @(
    "V72.4.3.2.29 ATTRACT_DECODER_RATE_AUDIO",
    "ResolveV724329AttractTempo",
    "0.9054",
    "NIHAV_DEDICATED_CPU_AFFINITY",
    "GetActiveProcessorCount",
    "nihav_dedicated_affinity",
    "DIRECT_PACKED_CHROMA_SMOOTH",
    "SampleV724329PackedChroma7x7"
)) {
    if (-not (
        $audio.Contains($marker) -or
        $affinity.Contains($marker) -or
        $chroma.Contains($marker))) {
        throw "[V72.4.3.2.29.0.1] Payload marker missing: $marker"
    }
}

Write-Host (
    "[V72.4.3.2.29.0.1] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files; PowerShell parsed; V29 payloads verified).")
