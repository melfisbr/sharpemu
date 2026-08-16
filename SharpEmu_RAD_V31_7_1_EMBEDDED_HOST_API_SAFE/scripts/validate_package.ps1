param([string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$manifest = Join-Path $root "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "[V72.4.3.2.31.7.1] SHA256SUMS.txt missing."
}

$entries = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "[V72.4.3.2.31.7.1] Invalid manifest line: $line"
    }
    $entries += [pscustomobject]@{ Hash=$matches[1].ToUpperInvariant(); Rel=$matches[2] }
}

foreach ($entry in $entries) {
    $path = Join-Path $root ($entry.Rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.1] Hashed file missing: $($entry.Rel)"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $entry.Hash) {
        throw "[V72.4.3.2.31.7.1] Hash mismatch: $($entry.Rel)"
    }
}

$psFiles = Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File
foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.31.7.1] PowerShell parse failed: $($file.Name): $($errors[0].Message)"
    }
}

$rad = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkExternalPlaybackV7243231.cs"))
$api = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkEmbeddedHostApiV724323171.cs"))
foreach ($marker in @(
    "RadBinkEmbeddedHostApiV724323171.TryAttach",
    'start.ArgumentList.Add("/I2");',
    "external_window_forbidden=True",
    "anchor=rad-embedded-playback-ready",
    ".NotifyPresentationStarted(moviePath)"
)) {
    if (-not $rad.Contains($marker)) {
        throw "[V72.4.3.2.31.7.1] RAD payload marker missing: $marker"
    }
}
foreach ($marker in @(
    "internal interface IRadBinkHostApi",
    "SetParent",
    "WsChild",
    "bink2.rad_host_attached",
    "render_location=sharpemu-child-window",
    "Marshal.SetLastPInvokeError(0)",
    "Marshal.GetLastPInvokeError()"
)) {
    if (-not $api.Contains($marker)) {
        throw "[V72.4.3.2.31.7.1] API payload marker missing: $marker"
    }
}
if ($rad.Contains("toolPath,`n                    toolPath,`n                    moviePath")) {
    throw "[V72.4.3.2.31.7.1] Duplicate toolPath constructor regression present."
}

if ($rad.Contains('start.ArgumentList.Add("/#");')) {
    throw "[V72.4.3.2.31.7.1] Invalid historical /# argument present."
}
if (Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -ieq 'radvideo64.exe' -or $_.Name -match '^bink.*\.dll$' }) {
    throw "[V72.4.3.2.31.7.1] Proprietary RAD/Bink binary must not be redistributed."
}

Write-Host ("[V72.4.3.2.31.7.1] PACKAGE VALIDATION PASSED (" + $entries.Count + " hashed files; PowerShell parsed; embedded host API verified; no RAD/Bink binary redistributed).") -ForegroundColor Green
