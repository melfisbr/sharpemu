param([string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$manifest = Join-Path $root "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "[V72.4.3.2.31.7.6] SHA256SUMS.txt missing."
}

$entries = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "[V72.4.3.2.31.7.6] Invalid manifest line: $line"
    }
    $entries += [pscustomobject]@{ Hash=$matches[1].ToUpperInvariant(); Rel=$matches[2] }
}

foreach ($entry in $entries) {
    $path = Join-Path $root ($entry.Rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.6] Hashed file missing: $($entry.Rel)"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $entry.Hash) {
        throw "[V72.4.3.2.31.7.6] Hash mismatch: $($entry.Rel)"
    }
}

$psFiles = Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter *.ps1 -File
foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "[V72.4.3.2.31.7.6] PowerShell parse failed: $($file.Name): $($errors[0].Message)"
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
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStarted(moviePath)",
    "BinkHostPlaybackAssist.NotifyHostMovieDecoderStopped(moviePath)",
    "bink2.rad_guest_hard_gate_started",
    "bink2.rad_guest_hard_gate_stopped",
    "bink2.rad_guest_work_throttle_begin",
    "bink2.rad_guest_work_throttle_heartbeat",
    "bink2.rad_guest_work_throttle_end",
    "SHARPEMU_RAD_GUEST_THROTTLE_HEARTBEAT_MS",
    "anchor=rad-embedded-playback-ready+guest-throttle-active",
    ".NotifyPresentationStarted(moviePath)"
)) {
    if (-not $rad.Contains($marker)) {
        throw "[V72.4.3.2.31.7.6] RAD payload marker missing: $marker"
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
    "SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS",
    "SHARPEMU_RAD_NOMINAL_END_GRACE_MS",
    "bink2.rad_visual_cutoff",
    "postroll_logo_visible=False",
    "bink2.rad_renderer_priority",
        "bink2.rad_renderer_revealed",
    "bink2.rad_nominal_end",
    "postroll_logo_suppressed=True",
    "SwpNoZOrder"
)) {
    if (-not $api.Contains($marker)) {
        throw "[V72.4.3.2.31.7.6] API payload marker missing: $marker"
    }
}
if ($rad.Contains("toolPath,`n                    toolPath,`n                    moviePath")) {
    throw "[V72.4.3.2.31.7.6] Duplicate toolPath constructor regression present."
}

if ($api.Contains("GetWindowTextW(") -or
    $api.Contains("GetWindowTextLengthW(") -or
    $api.Contains("GetWindowTitle(")) {
    throw "[V72.4.3.2.31.7.6] Blocking title-based HWND discovery regression present."
}

if ($api.Contains("SwpFrameChanged") -or $api.Contains("period: 100")) {
    throw "[V72.4.3.2.31.7.6] Continuous 100 ms FRAMECHANGED resize churn regression present."
}

if ($api.Contains("(window, _) =>")) {
    throw "[V72.4.3.2.31.7.6] C# discard-shadow regression present: EnumWindows lambda parameter named _."
}
if ($api.Contains("_ = GetWindowThreadProcessId") -and -not $api.Contains("(window, ignored) =>")) {
    throw "[V72.4.3.2.31.7.6] GetWindowThreadProcessId discard shape is not protected from lambda-parameter shadowing."
}

$throttleOld = [IO.File]::ReadAllText((Join-Path $root "payload\BinkHostPlaybackAssist.ShouldThrottleGuestGpu.old.txt"))
$throttleNew = [IO.File]::ReadAllText((Join-Path $root "payload\BinkHostPlaybackAssist.ShouldThrottleGuestGpu.new.txt"))
foreach ($marker in @(
    "SHARPEMU_BINK_THROTTLE_GUEST_GPU",
    "Volatile.Read(ref _activeHostMovieDecoders) > 0",
    "V72.4.3.2.31.7.6"
)) {
    if (-not $throttleNew.Contains($marker)) {
        throw "[V72.4.3.2.31.7.6] GPU throttle payload marker missing: $marker"
    }
}
if ($throttleOld -eq $throttleNew) {
    throw "[V72.4.3.2.31.7.6] GPU throttle old/new payloads are identical."
}

foreach ($pair in @(
    @("BinkHostPlaybackAssist.DecoderStart.old.txt",
      "BinkHostPlaybackAssist.DecoderStart.new.txt",
      "V72.4.3.2.14 HOST_MOVIE_CPU_GATE_BEGIN",
      "HostMovieExecutionGateV7243214.Begin()"),
    @("BinkHostPlaybackAssist.DecoderStop.old.txt",
      "BinkHostPlaybackAssist.DecoderStop.new.txt",
      "V72.4.3.2.14 HOST_MOVIE_CPU_GATE_END",
      "HostMovieExecutionGateV7243214.End()")
)) {
    $oldLifecycle = [IO.File]::ReadAllText((Join-Path $root ("payload\" + $pair[0])))
    $newLifecycle = [IO.File]::ReadAllText((Join-Path $root ("payload\" + $pair[1])))
    if ($oldLifecycle -eq $newLifecycle -or
        -not $newLifecycle.Contains($pair[2]) -or
        -not $newLifecycle.Contains($pair[3])) {
        throw "[V72.4.3.2.31.7.6] Decoder lifecycle HLE-gate payload is invalid: $($pair[1])"
    }
}

if ($rad.Contains("HostMovieExecutionGateV7243214.Begin()") -or
    $rad.Contains("HostMovieExecutionGateV7243214.End()")) {
    throw "[V72.4.3.2.31.7.6] RAD payload directly manipulates the HLE event gate; this would double-count V14/V15 lifecycle Begin/End."
}

$runner = [IO.File]::ReadAllText((Join-Path $root "scripts\run_diagnostic.ps1"))
foreach ($marker in @(
    '$env:SHARPEMU_BINK_THROTTLE_GUEST_GPU = "1"',
    '$env:SHARPEMU_BINK_SESSION_LOG = $binkSessionLog',
    "RAD_HARD_GATE_STARTED",
    "HOST_MOVIE_DECODER_STARTED",
    "ATTRACT_CORE_RES_NATIVE_ENTERS_DURING_HARD_GATE"
)) {
    if (-not $runner.Contains($marker)) {
        throw "[V72.4.3.2.31.7.6] Diagnostic hard-gate marker missing: $marker"
    }
}

$prewarm = [IO.File]::ReadAllText((Join-Path $root "scripts\prewarm_attract_audio.ps1"))
foreach ($marker in @("from12-v29-1p000.wav","atempo=1.0000","Rebuilding exact runtime attract")) {
    if (-not $prewarm.Contains($marker)) {
        throw "[V72.4.3.2.31.7.6] Attract audio prewarm marker missing: $marker"
    }
}

if ($rad.Contains("BinkHostPlaybackAssist.OnMovieFrame(") -or
    $rad.Contains("BinkHostPlaybackAssist.EndMovieSession(")) {
    throw "[V72.4.3.2.31.7.6] Compatibility stub lifecycle call returned to RAD payload."
}

if ($rad.Contains('start.ArgumentList.Add("/#");')) {
    throw "[V72.4.3.2.31.7.6] Invalid historical /# argument present."
}
if (Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -ieq 'radvideo64.exe' -or $_.Name -ieq 'binkplay.exe' -or $_.Name -match '^bink.*\.dll$' }) {
    throw "[V72.4.3.2.31.7.6] Proprietary RAD/Bink binary must not be redistributed."
}

Write-Host ("[V72.4.3.2.31.7.6] PACKAGE VALIDATION PASSED (" + $entries.Count + " hashed files; PowerShell parsed; RAD real decoder lifecycle + single-owner HLE event gate + GPU env throttle verified; no RAD/Bink binary redistributed).") -ForegroundColor Green
