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
        throw "[V72.4.3.2.31.5] Invalid manifest line."
    }

    $rel = $m.Groups[2].Value
    $path = Join-Path $root ($rel.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.5] Missing package file: $rel"
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $m.Groups[1].Value.ToLowerInvariant()) {
        throw "[V72.4.3.2.31.5] Hash mismatch: $rel"
    }
    $count++
}

foreach ($ps1 in Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.31.5] PowerShell parse failed: $($ps1.Name) :: $($errors[0].Message)"
    }

    $scriptText = [IO.File]::ReadAllText($ps1.FullName)
    if ([regex]::IsMatch($scriptText,'(?im)^\s*\$host\s*=')) {
        throw "[V72.4.3.2.31.5] Reserved PowerShell `$Host assignment in $($ps1.Name)."
    }
}

$rad = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkExternalPlaybackV7243231.cs"))

foreach ($marker in @(
    "V72.4.3.2.31.5",
    "RAD_BINKPLAY_CLI_FIX",
    'start.ArgumentList.Add("binkplay");',
    'start.ArgumentList.Add(moviePath);',
    "bink2.rad_command",
    "radvideo64.path",
    "SHARPEMU_RADVIDEO64"
)) {
    if (-not $rad.Contains($marker)) {
        throw "[V72.4.3.2.31.5] RAD bridge marker missing: $marker"
    }
}

if ($rad.Contains('start.ArgumentList.Add("/#");')) {
    throw "[V72.4.3.2.31.5] Invalid V31.4 '/#' BinkPlay argument is present in payload."
}

$forbidden = Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq "radvideo64.exe" -or $_.Name -match '(?i)^bink.*\.dll$' }

if ($null -ne $forbidden) {
    throw "[V72.4.3.2.31.5] Proprietary RAD/Bink binary unexpectedly present in package."
}

Write-Host (
    "[V72.4.3.2.31.5] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files; PowerShell parsed; invalid '/#' argument absent; no RAD/Bink binary redistributed).")
