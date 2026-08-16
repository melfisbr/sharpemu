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
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $m = [regex]::Match($line,'^([0-9a-fA-F]{64})  (.+)$')
    if (-not $m.Success) {
        throw "[V72.4.3.2.28.0.1] Invalid manifest line."
    }

    $rel = $m.Groups[2].Value
    $path = Join-Path $root ($rel.Replace('/','\'))

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.28.0.1] Missing package file: $rel"
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $m.Groups[1].Value.ToLowerInvariant()) {
        throw "[V72.4.3.2.28.0.1] Hash mismatch: $rel"
    }

    $count++
}

foreach ($ps1 in Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File) {
    $tokens = $null
    $errors = $null

    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,
        [ref]$tokens,
        [ref]$errors)

    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.28.0.1] PowerShell parse failed: $($ps1.Name) :: $($errors[0].Message)"
    }
}

# V72.4.3.2.28.0.1 POWERSHELL_HOST_AUTOMATIC_VARIABLE_GUARD
# PowerShell variable names are case-insensitive; $host collides with the
# built-in read-only $Host automatic variable.
foreach ($ps1 in Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File) {
    $scriptText = [IO.File]::ReadAllText($ps1.FullName)

    if ([regex]::IsMatch(
            $scriptText,
            '(?im)^\s*\$host\s*='))
    {
        throw "[V72.4.3.2.28.0.1] Reserved PowerShell automatic variable assignment detected in $($ps1.Name): `$host"
    }
}

$chroma = [IO.File]::ReadAllText((Join-Path $root "payload\BinkChromaRepairV7243227.cs"))
$audio = [IO.File]::ReadAllText((Join-Path $root "payload\BinkDemonSoulsIntroAudioV7243227.cs"))

foreach ($marker in @(
    "V72.4.3.2.28",
    "RepairBlockBias(",
    "DefaultBiasStrengthPercent = 75",
    "ATTRACT_AUDIO_RESYNC",
    "LOGO_AUDIO_SEGMENT_LIMIT"
)) {
    if (-not ($chroma.Contains($marker) -or $audio.Contains($marker))) {
        throw "[V72.4.3.2.28.0.1] Payload marker missing: $marker"
    }
}

Write-Host (
    "[V72.4.3.2.28.0.1] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files; PowerShell parsed; V28 payloads verified).")
