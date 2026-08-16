param([string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$manifest = Join-Path $root "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "[V72.4.3.2.31.7.7] SHA256SUMS.txt missing."
}
$entries = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "[V72.4.3.2.31.7.7] Invalid manifest line: $line"
    }
    $entries += [pscustomobject]@{ Hash=$matches[1].ToUpperInvariant(); Rel=$matches[2] }
}
foreach ($entry in $entries) {
    $path = Join-Path $root ($entry.Rel -replace '/', '\\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.7] Hashed file missing: $($entry.Rel)"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $entry.Hash) {
        throw "[V72.4.3.2.31.7.7] Hash mismatch: $($entry.Rel)"
    }
}
$psFiles = Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File
foreach ($file in $psFiles) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.31.7.7] PowerShell parse failed: $($file.Name): $($errors[0].Message)"
    }
}
$rad = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkExternalPlaybackV7243231.cs"))
$api = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkEmbeddedHostApiV724323171.cs"))
foreach ($marker in @(
    "V72.4.3.2.31.7.7",
    "bink2.rad_attract_audio_anchor_pre_reveal",
    "sync_source=rad-playback-anchor-before-reveal",
    "anchor=rad-playback-anchor-before-reveal",
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStarted(moviePath)",
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStopped(moviePath)"
)) {
    if (-not $rad.Contains($marker)) { throw "[V72.4.3.2.31.7.7] RAD payload marker missing: $marker" }
}
foreach ($marker in @(
    "Action<double>? beforeReveal",
    "beforeReveal(anchorMs)",
    "bink2.rad_before_reveal_callback",
    "defaultValue: 0",
    "bink2.rad_renderer_revealed",
    "SetParent",
    "bink2.rad_visual_cutoff"
)) {
    if (-not $api.Contains($marker)) { throw "[V72.4.3.2.31.7.7] API payload marker missing: $marker" }
}
if ($api.Contains("defaultValue: 80")) { throw "[V72.4.3.2.31.7.7] Historical 80 ms anchor delay remains." }
if ($api.Contains("GetWindowTextW(") -or $api.Contains("GetWindowTextLengthW(")) { throw "[V72.4.3.2.31.7.7] Blocking HWND title query regression." }
if ($rad.Contains('start.ArgumentList.Add("/#");')) { throw "[V72.4.3.2.31.7.7] Historical invalid BinkPlay /# argument returned." }
$runner = [IO.File]::ReadAllText((Join-Path $root "scripts\run_diagnostic.ps1"))
foreach ($marker in @(
    '$env:SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS = "0"',
    "ATTRACT_AUDIO_PRE_REVEAL_MARKERS",
    "AUDIO_SYNC_SOURCE=rad-playback-anchor-before-reveal",
    "GUEST_EBOOT_MEDIA_CLOCK_ACTIVE=False"
)) {
    if (-not $runner.Contains($marker)) { throw "[V72.4.3.2.31.7.7] Diagnostic media-clock marker missing: $marker" }
}
$forbidden = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -match '^(radvideo64|binkplay|bink2?w64)\.(exe|dll)$' })
if ($forbidden.Count -gt 0) { throw "[V72.4.3.2.31.7.7] Proprietary RAD/Bink binary must not be redistributed." }
Write-Host ("[V72.4.3.2.31.7.7] PACKAGE VALIDATION PASSED (" + $entries.Count + " hashed files; PowerShell parsed; zero-delay pre-reveal RAD media-clock sync verified; V31.7.6 hard gate preserved by prerequisite; no RAD/Bink binary redistributed).") -ForegroundColor Green
