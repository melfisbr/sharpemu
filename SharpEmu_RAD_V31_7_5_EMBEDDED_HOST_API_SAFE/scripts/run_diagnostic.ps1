param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin")

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$exe = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
foreach ($path in @($exe,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.5] Diagnostic prerequisite missing: $path"
    }
}

$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($rad)) {
    throw "[V72.4.3.2.31.7.5] RAD REQUIRED: radvideo64.exe not found."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $root ("SharpEmu_V72_4_3_2_31_7_5_RAD_EMBEDDED_RESULT_" + $stamp)
$stdout = Join-Path $out "stdout.log"
$stderr = Join-Path $out "stderr.log"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$names = @(
    "SHARPEMU_BINK_MODE",
    "SHARPEMU_RADVIDEO64",
    "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
    "SHARPEMU_DS_INTRO_EXTERNAL_AUDIO",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "SHARPEMU_RAD_EMBED_TIMEOUT_MS",
    "SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS",
    "SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS",
    "SHARPEMU_RAD_NOMINAL_END_GRACE_MS",
    "SHARPEMU_RAD_GUEST_THROTTLE_HEARTBEAT_MS"
)
$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name,[System.EnvironmentVariableTarget]::Process)
}

try {
    $env:SHARPEMU_BINK_MODE = "rad"
    $env:SHARPEMU_RADVIDEO64 = $rad
    $env:SHARPEMU_DS_ATTRACT_AUDIO_TEMPO = "1.0000"
    $env:SHARPEMU_DS_INTRO_EXTERNAL_AUDIO = "1"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS = "1500"
    $env:SHARPEMU_RAD_EMBED_TIMEOUT_MS = "6000"
    $env:SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS = "80"
    $env:SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS = "120"
    $env:SHARPEMU_RAD_NOMINAL_END_GRACE_MS = "0"
    $env:SHARPEMU_RAD_GUEST_THROTTLE_HEARTBEAT_MS = "200"

    Write-Host "[V72.4.3.2.31.7.5] RAD embedded-host test starting." -ForegroundColor Cyan
    Write-Host ("[V72.4.3.2.31.7.5] RAD=" + $rad)
    Write-Host "[V72.4.3.2.31.7.5] External top-level RAD window is forbidden. BinkPlay must be reparented into SharpEmu."
    Write-Host "[V72.4.3.2.31.7.5] Window discovery=PID/MainWindowHandle; blocking title queries are forbidden."
    Write-Host "[V72.4.3.2.31.7.5] Attach timeout=6000 ms; any failure kills new RAD/BinkPlay processes instead of leaving an external player."
    Write-Host "[V72.4.3.2.31.7.5] Attract audio anchor delay=80 ms after verified embedded playback readiness."
    Write-Host "[V72.4.3.2.31.7.5] PS5-like transition: renderer cuts 120 ms before nominal end and is killed at the nominal boundary; BinkPlay post-roll branding must never be visible."
    Write-Host "[V72.4.3.2.31.7.5] Resource policy: external RAD activates BinkHostPlaybackAssist; guest CPU is event-parked and payload-bearing guest GPU work is back-pressured while each movie owns the screen."
    Write-Host "[V72.4.3.2.31.7.5] Resize policy: child HWND changes only when SharpEmu client dimensions change (no 100 ms FRAMECHANGED churn)."

    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.31.7.5] Unsupported quote in Eboot path."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '"' + $Eboot + '"'
    $psi.WorkingDirectory = Split-Path -Parent $exe
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $watch = [Diagnostics.Stopwatch]::StartNew()
    if (-not $proc.Start()) {
        throw "[V72.4.3.2.31.7.5] Failed to start SharpEmu."
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $watch.Stop()

    $outText = $outTask.Result
    $errText = $errTask.Result
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    [IO.File]::WriteAllText($stdout,$outText,(New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText($stderr,$errText,(New-Object Text.UTF8Encoding($true)))

    $lines = @()
    $lines += ($errText -split "`r?`n")
    $lines += ($outText -split "`r?`n")

    $commands = @($lines | Where-Object { $_ -match 'bink2\.rad_command' -and $_ -match '/I2' })
    $audioTrackSelect = @($lines | Where-Object { $_ -match 'bink2\.rad_audio_track_select' })
    $rendererPriority = @($lines | Where-Object { $_ -match 'bink2\.rad_renderer_priority ' })
    $revealed = @($lines | Where-Object { $_ -match 'bink2\.rad_renderer_revealed' })
    $visualCutoffs = @($lines | Where-Object { $_ -match 'bink2\.rad_visual_cutoff' -and $_ -match 'postroll_logo_visible=False' })
    $nominalEnds = @($lines | Where-Object { $_ -match 'bink2\.rad_nominal_end' -and $_ -match 'postroll_logo_suppressed=True' })
    $guestThrottleBegin = @($lines | Where-Object { $_ -match 'bink2\.rad_guest_work_throttle_begin' })
    $guestThrottleHeartbeat = @($lines | Where-Object { $_ -match 'bink2\.rad_guest_work_throttle_heartbeat' })
    $guestThrottleEnd = @($lines | Where-Object { $_ -match 'bink2\.rad_guest_work_throttle_end' })
    $guestGpuBackpressure = @($lines | Where-Object { $_ -match 'vk\.guest_queue_backpressure' })
    $resizeMutations = @($lines | Where-Object { $_ -match 'bink2\.rad_host_resize' -and $_ -match 'changed=True' })
    $started = @($lines | Where-Object { $_ -match 'bink2\.rad_required_started' })
    $attachBegin = @($lines | Where-Object { $_ -match 'bink2\.rad_host_attach_begin' })
    $hostWindowReady = @($lines | Where-Object { $_ -match 'bink2\.rad_host_window_ready' })
    $rendererWindowReady = @($lines | Where-Object { $_ -match 'bink2\.rad_renderer_window_ready' })
    $rendererBound = @($lines | Where-Object { $_ -match 'bink2\.rad_renderer_bound' })
    $attachWait = @($lines | Where-Object { $_ -match 'bink2\.rad_host_attach_wait' })
    $hostAttached = @($lines | Where-Object { $_ -match 'bink2\.rad_host_attached' })
    $bridgeAttached = @($lines | Where-Object { $_ -match 'Bink RAD bridge attached:' })
    $hostReleased = @($lines | Where-Object { $_ -match 'bink2\.rad_host_released' })
    $hostFailures = @($lines | Where-Object {
        $_ -match 'bink2\.rad_host_(?:window_missing|style_read_failed|style_write_failed|setparent_failed|parent_verify_failed|resize_failed)' -or
        $_ -match 'bink2\.rad_embedded_host_required_failed'
    })
    $fallback = @($lines | Where-Object {
        $_ -match 'Bink2 NIHAV bridge attached:' -or
        $_ -match 'bink2\.nihav_ready'
    })
    $headers = @($lines | Where-Object { $_ -match 'bink2\.rad_audio_header' })
    $attractSidecar = @($lines | Where-Object { $_ -match 'bink2\.rad_attract_audio_sidecar' })
    $attractAudioStarts = @($lines | Where-Object {
        $_ -match 'bink2\.ds_intro_audio_start' -and $_ -match "file='attract_movie\.bk2'"
    })
    $unhandled = @($lines | Where-Object { $_ -match 'Unhandled exception' })

    $hostIndex = -1
    $audioIndex = -1
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($hostIndex -lt 0 -and
            $lines[$i] -match 'bink2\.rad_host_attached' -and
            $lines[$i] -match "file='attract_movie\.bk2'") {
            $hostIndex = $i
        }
        if ($audioIndex -lt 0 -and
            $lines[$i] -match 'bink2\.ds_intro_audio_start' -and
            $lines[$i] -match "file='attract_movie\.bk2'") {
            $audioIndex = $i
        }
    }
    $audioAfterHost = $hostIndex -ge 0 -and $audioIndex -gt $hostIndex
    $hostDiscoveryStalled =
        $started.Count -gt 0 -and
        $attachBegin.Count -gt 0 -and
        $hostAttached.Count -eq 0 -and
        $hostFailures.Count -eq 0

    $renderLocation =
        if ($hostAttached.Count -gt 0) {
            "sharpemu-child-window"
        } else {
            "external-or-unverified"
        }

    $peakWorkingMb = 0
    $peakPrivateMb = 0
    $peakGcMb = 0
    foreach ($line in $lines) {
        if ($line -match '\[V74\.0\.8\.1\]\[MEM\].*?gc_mb=(\d+).*?working_mb=(\d+).*?private_mb=(\d+)') {
            $gc = [int]$matches[1]
            $working = [int]$matches[2]
            $private = [int]$matches[3]
            if ($gc -gt $peakGcMb) { $peakGcMb = $gc }
            if ($working -gt $peakWorkingMb) { $peakWorkingMb = $working }
            if ($private -gt $peakPrivateMb) { $peakPrivateMb = $private }
        }
    }

    $strictProof =
        $commands.Count -ge 3 -and
        $audioTrackSelect.Count -ge 1 -and
        $revealed.Count -ge 3 -and
        $visualCutoffs.Count -ge 3 -and
        $nominalEnds.Count -ge 3 -and
        $guestThrottleBegin.Count -ge 3 -and
        $guestThrottleEnd.Count -ge 3 -and
        $started.Count -ge 3 -and
        $attachBegin.Count -ge 3 -and
        $hostWindowReady.Count -ge 3 -and
        $rendererWindowReady.Count -ge 3 -and
        $rendererBound.Count -ge 3 -and
        $hostAttached.Count -ge 3 -and
        $bridgeAttached.Count -ge 3 -and
        $hostFailures.Count -eq 0 -and
        -not $hostDiscoveryStalled -and
        $fallback.Count -eq 0 -and
        $attractSidecar.Count -ge 1 -and
        $attractAudioStarts.Count -ge 1 -and
        $audioAfterHost -and
        $unhandled.Count -eq 0

    $summary = @(
        "SharpEmu V72.4.3.2.31.7.5 RAD PID/HWND EMBEDDED HOST RESULT",
        "=================================================",
        ("WALL_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $exitCode),
        "ACTIVE_BINK_MODE=rad",
        ("RAD_COMMAND_I2=" + $commands.Count),
        ("RAD_AUDIO_TRACK_SELECT=" + $audioTrackSelect.Count),
        ("RAD_RENDERER_PRIORITY_ABOVENORMAL=" + $rendererPriority.Count),
        ("RAD_RENDERER_REVEALED=" + $revealed.Count),
        ("RAD_VISUAL_CUTOFFS=" + $visualCutoffs.Count),
        ("RAD_NOMINAL_END_SUPPRESSIONS=" + $nominalEnds.Count),
        ("RAD_GUEST_THROTTLE_BEGIN=" + $guestThrottleBegin.Count),
        ("RAD_GUEST_THROTTLE_HEARTBEATS=" + $guestThrottleHeartbeat.Count),
        ("RAD_GUEST_THROTTLE_END=" + $guestThrottleEnd.Count),
        ("GUEST_GPU_BACKPRESSURE_MARKERS=" + $guestGpuBackpressure.Count),
        ("RAD_RESIZE_MUTATIONS=" + $resizeMutations.Count),
        ("RAD_STARTED=" + $started.Count),
        ("RAD_HOST_ATTACH_BEGIN=" + $attachBegin.Count),
        ("RAD_HOST_WINDOW_READY=" + $hostWindowReady.Count),
        ("RAD_RENDERER_WINDOW_READY=" + $rendererWindowReady.Count),
        ("RAD_RENDERER_BOUND=" + $rendererBound.Count),
        ("RAD_HOST_ATTACH_WAIT_MARKERS=" + $attachWait.Count),
        ("RAD_HOST_ATTACHED=" + $hostAttached.Count),
        ("RAD_BRIDGE_ATTACHED=" + $bridgeAttached.Count),
        ("RAD_HOST_RELEASED=" + $hostReleased.Count),
        ("RAD_EMBEDDED_HOST_FAILURES=" + $hostFailures.Count),
        ("RAD_HOST_DISCOVERY_STALLED=" + $hostDiscoveryStalled),
        ("NIHAV_FALLBACK_HITS=" + $fallback.Count),
        ("RAD_AUDIO_HEADER_MARKERS=" + $headers.Count),
        ("ATTRACT_RAD_SIDECAR_MARKERS=" + $attractSidecar.Count),
        ("ATTRACT_AUDIO_STARTS=" + $attractAudioStarts.Count),
        ("ATTRACT_AUDIO_ANCHOR_AFTER_HOST=" + $audioAfterHost),
        "ATTRACT_AUDIO_OFFSET_SECONDS=12.000",
        "ATTRACT_AUDIO_TEMPO=1.0000",
        "ATTRACT_AUDIO_ANCHOR_DELAY_MS=80",
        "RAD_VISUAL_CUTOFF_LEAD_MS=120",
        "RAD_NOMINAL_END_GRACE_MS=0",
        "RAD_GUEST_THROTTLE_HEARTBEAT_MS=200",
        ("PEAK_GC_MB=" + $peakGcMb),
        ("PEAK_WORKING_MB=" + $peakWorkingMb),
        ("PEAK_PRIVATE_MB=" + $peakPrivateMb),
        "RAD_POSTROLL_LOGO_POLICY=visual-cut-120ms-before-corrected-nominal;kill-at-corrected-nominal",
        "RAD_GUEST_WORK_POLICY=BinkHostPlaybackAssist CPU-event-park + GPU-payload-backpressure",
        "RAD_RESIZE_POLICY=only-on-client-size-change",
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count),
        ("RAD_RENDER_LOCATION=" + $renderLocation),
        "WINDOW_DISCOVERY=pid-mainwindow-no-windowtext",
        "TRUE_IN_PROCESS_BINK_SDK=False",
        ("STRICT_RAD_EMBEDDED_PROOF=" + $strictProof)
    )

    [IO.File]::WriteAllLines((Join-Path $out "SUMMARY.txt"),[string[]]$summary,(New-Object Text.UTF8Encoding($true)))

    $relevant = @($lines | Where-Object {
        $_ -match 'bink2\.' -or
        $_ -match 'Bink RAD bridge' -or
        $_ -match 'Bink2 NIHAV bridge' -or
        $_ -match 'vk\.guest_queue_backpressure' -or
        $_ -match '\[V74\.0\.8\.1\]\[MEM\]' -or
        $_ -match 'Unhandled exception'
    })
    [IO.File]::WriteAllLines((Join-Path $out "BINK_RELEVANT.log"),[string[]]$relevant,(New-Object Text.UTF8Encoding($true)))

    $zip = $out + ".zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal

    Write-Host ""
    Get-Content -LiteralPath (Join-Path $out "SUMMARY.txt")
    Write-Host ""
    Write-Host ("[V72.4.3.2.31.7.5] RESULT ZIP: " + $zip) -ForegroundColor Green

    if (-not $strictProof) {
        throw "[V72.4.3.2.31.7.5] STRICT RAD EMBEDDED HOST PROOF FAILED. Result ZIP preserved."
    }

    Write-Host "[V72.4.3.2.31.7.5] STRICT RAD EMBEDDED HOST PROOF PASSED." -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name,$previous[$name],[System.EnvironmentVariableTarget]::Process)
    }
}
