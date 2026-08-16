param([string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$manifest = Join-Path $root "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "[V72.4.3.2.31.7.8] SHA256SUMS.txt missing."
}

$entries = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "[V72.4.3.2.31.7.8] Invalid manifest line: $line"
    }
    $entries += [pscustomobject]@{ Hash=$matches[1].ToUpperInvariant(); Rel=$matches[2] }
}
foreach ($entry in $entries) {
    $path = Join-Path $root ($entry.Rel -replace '/', '\\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.8] Hashed file missing: $($entry.Rel)"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $entry.Hash) {
        throw "[V72.4.3.2.31.7.8] Hash mismatch: $($entry.Rel)"
    }
}

$psFiles = Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File
foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.31.7.8] PowerShell parse failed: $($file.Name): $($errors[0].Message)"
    }
}

$fragment = [IO.File]::ReadAllText((Join-Path $root "patch\HostMovieBridge.TryStartConfiguredBootSequence.v3178.csfrag"))
foreach ($marker in @(
    "private static void TryStartConfiguredBootSequence()",
    "ps_studios_logo.bk2",
    "logo_intro.bk2",
    "logo_intro_loop.bk2",
    "main_menu_ngp, attract_movie, story movies and credits are guest-driven",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS"
)) {
    if (-not $fragment.Contains($marker)) {
        throw "[V72.4.3.2.31.7.8] Canonical fragment marker missing: $marker"
    }
}
if ($fragment.Contains('"attract_movie.bk2"')) {
    throw "[V72.4.3.2.31.7.8] Canonical fragment must not include attract_movie as a host boot asset."
}

$runner = [IO.File]::ReadAllText((Join-Path $root "scripts\run_diagnostic.ps1"))
foreach ($marker in @(
    '$env:SHARPEMU_BINK_BOOT_SEQUENCE = $null',
    '$env:SHARPEMU_BINK_AUTO_BOOT = "1"',
    '$env:SHARPEMU_LOG_IO_FILTER = "pr_demons_souls_intro"',
    "HOST_ATTRACT_INJECTION_MARKERS",
    "NATURAL_ATTRACT_OBSERVED",
    "MOVIE_CLOCK_SOURCE=",
    "AUDIO_CLOCK_EVIDENCE=",
    "STRICT_GUEST_MEDIA_HANDOFF_PROOF="
)) {
    if (-not $runner.Contains($marker)) {
        throw "[V72.4.3.2.31.7.8] Guest-media diagnostic marker missing: $marker"
    }
}

$apply = [IO.File]::ReadAllText((Join-Path $root "scripts\apply_build.ps1"))
foreach ($marker in @(
    "Get-CSharpMethodSpanV3178",
    "HostMovieBridge.TryStartConfiguredBootSequence.v3178.csfrag",
    "SharpEmu.Libs build failed",
    "SharpEmu.CLI build failed"
)) {
    if (-not $apply.Contains($marker)) {
        throw "[V72.4.3.2.31.7.8] Apply structural-safety marker missing: $marker"
    }
}

$forbidden = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Name -match '^(radvideo64|binkplay|bink2?w64)\.(exe|dll)$'
})
if ($forbidden.Count -gt 0) {
    throw "[V72.4.3.2.31.7.8] Proprietary RAD/Bink binary must not be redistributed."
}

Write-Host ("[V72.4.3.2.31.7.8] PACKAGE VALIDATION PASSED (" + $entries.Count + " hashed files; PowerShell parsed; canonical guest-driven boot boundary verified; filtered EBOOT-audio evidence probe verified; no RAD/Bink binary redistributed).") -ForegroundColor Green
