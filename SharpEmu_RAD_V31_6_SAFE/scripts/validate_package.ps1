param([string]$PackageRoot="")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$candidate = $PackageRoot
if ([string]::IsNullOrWhiteSpace($candidate)) {
    $candidate = Split-Path -Parent $PSScriptRoot
}

$candidate = $candidate.Trim().Trim('"').TrimEnd('\','/')
$root = (Resolve-Path -LiteralPath $candidate).Path
$manifest = Join-Path $root "SHA256SUMS.txt"
$count = 0

foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $m = [regex]::Match($line,'^([0-9a-fA-F]{64})  (.+)$')
    if (-not $m.Success) {
        throw "[V72.4.3.2.31.6] Invalid manifest line."
    }

    $rel = $m.Groups[2].Value
    $path = Join-Path $root ($rel.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.6] Missing package file: $rel"
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $m.Groups[1].Value.ToLowerInvariant()) {
        throw "[V72.4.3.2.31.6] Hash mismatch: $rel"
    }
    $count++
}

foreach ($ps1 in Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.31.6] PowerShell parse failed: $($ps1.Name) :: $($errors[0].Message)"
    }

    $scriptText = [IO.File]::ReadAllText($ps1.FullName)
    if ([regex]::IsMatch($scriptText,'(?im)^\s*\$host\s*=')) {
        throw "[V72.4.3.2.31.6] Reserved PowerShell `$Host assignment in $($ps1.Name)."
    }
}

$rad = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkExternalPlaybackV7243231.cs"))

foreach ($marker in @(
    "V72.4.3.2.31.6",
    "RAD_ATTRACT_AUDIO_NATIVE_RATE",
    "TryReadBinkAudioTrackIds",
    "bink2.rad_audio_header",
    "bink2.rad_attract_audio_sidecar",
    "BinkDemonSoulsIntroAudioV7243227.PrepareAttach",
    "BinkDemonSoulsIntroAudioV7243227.StopForMovie",
    '"1.0000"',
    'start.ArgumentList.Add("binkplay");',
    'start.ArgumentList.Add(moviePath);'
)) {
    if (-not $rad.Contains($marker)) {
        throw "[V72.4.3.2.31.6] RAD payload marker missing: $marker"
    }
}

if ($rad.Contains('start.ArgumentList.Add("/#");')) {
    throw "[V72.4.3.2.31.6] Invalid historical '/#' argument is present."
}

$forbidden = Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -ieq "radvideo64.exe" -or
        $_.Name -ieq "binkplay.exe" -or
        $_.Name -match '(?i)^bink.*\.dll$' -or
        $_.Extension -ieq ".at9" -or
        $_.Extension -ieq ".wav"
    }

if ($null -ne $forbidden) {
    throw "[V72.4.3.2.31.6] Proprietary/game audio or RAD/Bink binary unexpectedly present in package."
}

Write-Host (
    "[V72.4.3.2.31.6] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files; PowerShell parsed; Bink header parser + zero-track attract sidecar verified; no RAD/game media redistributed).")
