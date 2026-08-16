param([string]$PackageRoot="")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$candidate = $PackageRoot
if ([string]::IsNullOrWhiteSpace($candidate)) {
    $candidate = Split-Path -Parent $PSScriptRoot
}

$candidate = ($candidate -replace '^\s+|\s+$','')
$candidate = ($candidate -replace '^"|"$','')
$candidate = ($candidate -replace '[\\/]+$','')
$root = (Resolve-Path -LiteralPath $candidate).Path

$manifest = Join-Path $root "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "[V72.4.3.2.27] SHA256SUMS.txt missing."
}

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
        throw "[V72.4.3.2.27] Invalid manifest line."
    }

    $relative = $match.Groups[2].Value
    $path =
        Join-Path $root ($relative.Replace('/','\'))

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.27] Package file missing: $relative"
    }

    $actual =
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).
        Hash.ToLowerInvariant()

    if ($actual -ne $match.Groups[1].Value.ToLowerInvariant()) {
        throw "[V72.4.3.2.27] Hash mismatch: $relative"
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
            "[V72.4.3.2.27] PowerShell parse failed: " +
            $ps1.Name +
            " :: " +
            $errors[0].Message)
    }
}

$native =
    Join-Path $root "payload\nihav-tool-native.exe"
$nativeHash =
    (Get-FileHash -LiteralPath $native -Algorithm SHA256).
    Hash.ToLowerInvariant()

if ($nativeHash -ne
    "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18") {
    throw "[V72.4.3.2.27] Native NIHAV payload hash mismatch."
}

$chroma =
    [IO.File]::ReadAllText(
        (Join-Path $root "payload\BinkChromaRepairV7243227.cs"))
$audio =
    [IO.File]::ReadAllText(
        (Join-Path $root "payload\BinkDemonSoulsIntroAudioV7243227.cs"))
$neutral =
    [IO.File]::ReadAllText(
        (Join-Path $root "payload\neutral_v27.new.txt"))

foreach ($marker in @(
    "V72.4.3.2.27",
    "BinkChromaRepairV7243227",
    "ChromaBlock = 8",
    "DefaultThreshold = 24",
    "BinkDemonSoulsIntroAudioV7243227",
    "pr_demons_souls_intro_music.at9",
    "pr_demons_souls_intro_sfx.at9",
    "pr_demons_souls_intro_vo.at9",
    "CENTERED_CHROMA_NEUTRAL_GATE_FIX"
)) {
    if (-not (
        $chroma.Contains($marker) -or
        $audio.Contains($marker) -or
        $neutral.Contains($marker))) {
        throw "[V72.4.3.2.27] Payload marker missing: $marker"
    }
}

Write-Host (
    "[V72.4.3.2.27] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files; PowerShell parsed; native NIHAV payload verified).")
