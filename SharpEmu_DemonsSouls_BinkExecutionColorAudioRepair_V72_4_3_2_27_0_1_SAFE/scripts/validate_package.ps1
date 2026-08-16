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
    throw "[V72.4.3.2.27.0.1] SHA256SUMS.txt missing."
}

$count = 0

foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $match = [regex]::Match($line,'^([0-9a-fA-F]{64})  (.+)$')
    if (-not $match.Success) {
        throw "[V72.4.3.2.27.0.1] Invalid manifest line."
    }

    $relative = $match.Groups[2].Value
    $path = Join-Path $root ($relative.Replace('/','\'))

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.27.0.1] Package file missing: $relative"
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected = $match.Groups[1].Value.ToLowerInvariant()

    if ($actual -ne $expected) {
        throw "[V72.4.3.2.27.0.1] Hash mismatch: $relative"
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
        throw "[V72.4.3.2.27.0.1] PowerShell parse failed: $($ps1.Name) :: $($errors[0].Message)"
    }
}

$payload = Join-Path $root "payload\nihav-tool-native.exe"
$payloadHash = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()

if ($payloadHash -ne "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18") {
    throw "[V72.4.3.2.27.0.1] Native NIHAV payload hash mismatch."
}

$diagnostic = [IO.File]::ReadAllText((Join-Path $root "scripts\run_diagnostic.ps1"))
foreach ($marker in @(
    "[System.EnvironmentVariableTarget]::Process",
    "NIHAV_RUNTIME_HASH_OK=",
    "INTRO_AUDIO_STARTS=",
    "CLOCK_CATCHUP_EVENTS=",
    "RESULT ZIP:"
)) {
    if (-not $diagnostic.Contains($marker)) {
        throw "[V72.4.3.2.27.0.1] Diagnostic marker missing: $marker"
    }
}

$apply = [IO.File]::ReadAllText((Join-Path $root "scripts\apply_build.ps1"))
foreach ($marker in @(
    "V72.4.3.2.27.0.1 PERSISTENT_NATIVE_NIHAV_DEPLOY",
    ".sharpemu-tools\bink2\optimized\nihav-tool-v27-native.exe",
    "CopySharpEmuNihavToolV6113166",
    "FINAL_NIHAV_SHA256"
)) {
    if (-not $apply.Contains($marker)) {
        throw "[V72.4.3.2.27.0.1] Apply marker missing: $marker"
    }
}

Write-Host (
    "[V72.4.3.2.27.0.1] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files; all PowerShell scripts parsed; native payload verified).")
