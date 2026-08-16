param([string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$manifest = Join-Path $root "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "[V72.4.3.2.31.7.4] SHA256SUMS.txt missing."
}

$entries = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "[V72.4.3.2.31.7.4] Invalid manifest line: $line"
    }
    $entries += [pscustomobject]@{ Hash=$matches[1].ToUpperInvariant(); Rel=$matches[2] }
}

foreach ($entry in $entries) {
    $path = Join-Path $root ($entry.Rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.4] Hashed file missing: $($entry.Rel)"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $entry.Hash) {
        throw "[V72.4.3.2.31.7.4] Hash mismatch: $($entry.Rel)"
    }
}

$psFiles = Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File
foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.31.7.4] PowerShell parse failed: $($file.Name): $($errors[0].Message)"
    }
}

$rad = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkExternalPlaybackV7243231.cs"))
$api = [IO.File]::ReadAllText((Join-Path $root "payload\RadBinkEmbeddedHostApiV724323171.cs"))
foreach ($marker in @(
    "RadBinkEmbeddedHostApiV724323171.TryAttach",
    "CaptureRadProcessSnapshot",
    "KillSpawnedRadProcesses",
    "TryReadBinkHeaderMetadata",
    'start.ArgumentList.Add("/I2");',
    'start.ArgumentList.Add("/Z0");',
    "bink2.rad_audio_track_select",
    "external_window_forbidden=True",
    "bink2.rad_renderer_bound",
    "anchor=rad-embedded-playback-ready",
    ".NotifyPresentationStarted(moviePath)"
)) {
    if (-not $rad.Contains($marker)) {
        throw "[V72.4.3.2.31.7.4] RAD payload marker missing: $marker"
    }
}
foreach ($marker in @(
    "internal interface IRadBinkHostApi",
    "process.MainWindowHandle",
    "CaptureRadProcessSnapshot",
    "bink2.rad_host_attach_begin",
    "bink2.rad_renderer_window_ready",
    "discovery=pid-mainwindow-no-windowtext",
    "SetParent",
    "GetParent",
    "IsChild",
    "WsChild",
    "bink2.rad_host_attached",
    "verified_parent=True",
    "render_location=sharpemu-child-window",
    "Marshal.SetLastPInvokeError(0)",
    "Marshal.GetLastPInvokeError()",
    "SHARPEMU_RAD_NOMINAL_END_GRACE_MS",
    "bink2.rad_renderer_priority",
        "bink2.rad_renderer_revealed",
    "bink2.rad_nominal_end",
    "postroll_logo_suppressed=True",
    "SwpNoZOrder"
)) {
    if (-not $api.Contains($marker)) {
        throw "[V72.4.3.2.31.7.4] API payload marker missing: $marker"
    }
}
if ($rad.Contains("toolPath,`n                    toolPath,`n                    moviePath")) {
    throw "[V72.4.3.2.31.7.4] Duplicate toolPath constructor regression present."
}

if ($api.Contains("GetWindowTextW(") -or
    $api.Contains("GetWindowTextLengthW(") -or
    $api.Contains("GetWindowTitle(")) {
    throw "[V72.4.3.2.31.7.4] Blocking title-based HWND discovery regression present."
}

if ($api.Contains("SwpFrameChanged") -or $api.Contains("period: 100")) {
    throw "[V72.4.3.2.31.7.4] Continuous 100 ms FRAMECHANGED resize churn regression present."
}

if ($api.Contains("(window, _) =>")) {
    throw "[V72.4.3.2.31.7.4] C# discard-shadow regression present: EnumWindows lambda parameter named _."
}
if ($api.Contains("_ = GetWindowThreadProcessId") -and -not $api.Contains("(window, ignored) =>")) {
    throw "[V72.4.3.2.31.7.4] GetWindowThreadProcessId discard shape is not protected from lambda-parameter shadowing."
}

$prewarm = [IO.File]::ReadAllText((Join-Path $root "scripts\prewarm_attract_audio.ps1"))
foreach ($marker in @("from12-v29-1p000.wav","atempo=1.0000","Rebuilding exact runtime attract")) {
    if (-not $prewarm.Contains($marker)) {
        throw "[V72.4.3.2.31.7.4] Attract audio prewarm marker missing: $marker"
    }
}

if ($rad.Contains('start.ArgumentList.Add("/#");')) {
    throw "[V72.4.3.2.31.7.4] Invalid historical /# argument present."
}
if (Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -ieq 'radvideo64.exe' -or $_.Name -ieq 'binkplay.exe' -or $_.Name -match '^bink.*\.dll$' }) {
    throw "[V72.4.3.2.31.7.4] Proprietary RAD/Bink binary must not be redistributed."
}

Write-Host ("[V72.4.3.2.31.7.4] PACKAGE VALIDATION PASSED (" + $entries.Count + " hashed files; PowerShell parsed; embedded host API verified; no RAD/Bink binary redistributed).") -ForegroundColor Green
