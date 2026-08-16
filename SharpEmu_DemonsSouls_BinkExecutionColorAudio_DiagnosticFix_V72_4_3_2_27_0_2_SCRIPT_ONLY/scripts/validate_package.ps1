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
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "[V72.4.3.2.27.0.2] SHA256SUMS.txt missing."
}

$count = 0

foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $match = [regex]::Match($line,'^([0-9a-fA-F]{64})  (.+)$')
    if (-not $match.Success) {
        throw "[V72.4.3.2.27.0.2] Invalid manifest line."
    }

    $relative = $match.Groups[2].Value
    $path = Join-Path $root ($relative.Replace('/','\'))

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.27.0.2] Package file missing: $relative"
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected = $match.Groups[1].Value.ToLowerInvariant()

    if ($actual -ne $expected) {
        throw "[V72.4.3.2.27.0.2] Hash mismatch: $relative"
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
        throw "[V72.4.3.2.27.0.2] PowerShell parse failed: $($ps1.Name) :: $($errors[0].Message)"
    }
}

$runner = [IO.File]::ReadAllText((Join-Path $root "scripts\run_diagnostic.ps1"))

foreach ($marker in @(
    "V72.4.3.2.27.0.2 POWERSHELL_5_1_PROCESS_ARGUMENTS_FIX",
    '$psi.Arguments =',
    "[System.EnvironmentVariableTarget]::Process",
    "NIHAV_RUNTIME_HASH_OK=",
    "INTRO_AUDIO_STARTS=",
    "CLOCK_CATCHUP_EVENTS=",
    "RESULT ZIP:"
)) {
    if (-not $runner.Contains($marker)) {
        throw "[V72.4.3.2.27.0.2] Runner marker missing: $marker"
    }
}

if ($runner.Contains('$psi.ArgumentList')) {
    throw "[V72.4.3.2.27.0.2] PowerShell 5.1-incompatible ProcessStartInfo.ArgumentList usage is still present."
}

Write-Host (
    "[V72.4.3.2.27.0.2] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files; PowerShell parsed; ProcessStartInfo.Arguments compatibility verified).")
