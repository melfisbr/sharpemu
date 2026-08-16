param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin")

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$exe = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
foreach ($path in @($exe,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.8] Diagnostic prerequisite missing: $path"
    }
}

$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($rad)) {
    throw "[V72.4.3.2.31.7.8] RAD REQUIRED: radvideo64.exe not found."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $root ("SharpEmu_V72_4_3_2_31_7_8_GUEST_MEDIA_RESULT_" + $stamp)
$stdout = Join-Path $out "stdout.log"
$stderr = Join-Path $out "stderr.log"
$binkSessionLog = Join-Path $out "bink_session.log"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$names = @(
    "SHARPEMU_BINK_MODE",
    "SHARPEMU_RADVIDEO64",
    "SHARPEMU_BINK_BOOT_SEQUENCE",
    "SHARPEMU_BINK_AUTO_BOOT",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
    "SHARPEMU_DS_INTRO_EXTERNAL_AUDIO",
    "SHARPEMU_RAD_EMBED_TIMEOUT_MS",
    "SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS",
    "SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS",
    "SHARPEMU_RAD_NOMINAL_END_GRACE_MS",
    "SHARPEMU_RAD_GUEST_THROTTLE_HEARTBEAT_MS",
    "SHARPEMU_BINK_THROTTLE_GUEST_GPU",
    "SHARPEMU_BINK_SESSION_LOG",
    "SHARPEMU_POST_BINK_TRIM_WORKING_SET",
    "SHARPEMU_LOG_IO",
    "SHARPEMU_LOG_IO_FILTER"
)
$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name,[System.EnvironmentVariableTarget]::Process)
}

try {
    $env:SHARPEMU_BINK_MODE = "rad"
    $env:SHARPEMU_RADVIDEO64 = $rad
    $env:SHARPEMU_BINK_BOOT_SEQUENCE = $null
    $env:SHARPEMU_BINK_AUTO_BOOT = "1"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS = "1500"
    $env:SHARPEMU_DS_ATTRACT_AUDIO_TEMPO = "1.0000"
    $env:SHARPEMU_DS_INTRO_EXTERNAL_AUDIO = "1"
    $env:SHARPEMU_RAD_EMBED_TIMEOUT_MS = "6000"
    $env:SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS = "0"
    $env:SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS = "120"
    $env:SHARPEMU_RAD_NOMINAL_END_GRACE_MS = "0"
    $env:SHARPEMU_RAD_GUEST_THROTTLE_HEARTBEAT_MS = "200"
    $env:SHARPEMU_BINK_THROTTLE_GUEST_GPU = "1"
    $env:SHARPEMU_BINK_SESSION_LOG = $binkSessionLog
    $env:SHARPEMU_POST_BINK_TRIM_WORKING_SET = "1"
    $env:SHARPEMU_LOG_IO = "1"
    $env:SHARPEMU_LOG_IO_FILTER = "pr_demons_souls_intro"

    Write-Host "[V72.4.3.2.31.7.8] Guest-media handoff test starting." -ForegroundColor Cyan
    Write-Host ("[V72.4.3.2.31.7.8] RAD=" + $rad)
    Write-Host "[V72.4.3.2.31.7.8] Explicit SHARPEMU_BINK_BOOT_SEQUENCE cleared."
    Write-Host "[V72.4.3.2.31.7.8] Host fallback boundary: ps_studios_logo -> logo_intro -> logo_intro_loop (if present)."
    Write-Host "[V72.4.3.2.31.7.8] attract_movie is guest/EBOOT-owned and must never appear in host auto_boot_order."
    Write-Host "[V72.4.3.2.31.7.8] RAD embedded host + V31.7.6 hard gate + zero-delay anchor preserved."
    Write-Host "[V72.4.3.2.31.7.8] Narrow guest-audio I/O probe: SHARPEMU_LOG_IO_FILTER=pr_demons_souls_intro."
    Write-Host "[V72.4.3.2.31.7.8] Sidecar remains compatibility fallback until guest audio ownership is proven."

    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.31.7.8] Unsupported quote in Eboot path."
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
        throw "[V72.4.3.2.31.7.8] Failed to start SharpEmu."
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

    $errLines = @($errText -split "`r?`n")
    $outLines = @($outText -split "`r?`n")
    $sessionLines = @()
    if (Test-Path -LiteralPath $binkSessionLog -PathType Leaf) {
        $sessionLines = @(Get-Content -LiteralPath $binkSessionLog)
    }
    $lines = @($errLines + $outLines + $sessionLines)

    $autoOrders = @($lines | Where-Object { $_ -match 'bink2\.auto_boot_order' })
    $badAutoOrders = @($autoOrders | Where-Object { $_ -match 'attract_movie\.bk2' })
    $canonicalAutoOrders = @($autoOrders | Where-Object {
        $_ -match 'ps_studios_logo\.bk2\s*->\s*logo_intro\.bk2' -and
        $_ -notmatch 'attract_movie\.bk2'
    })
    $hostAttractInjection = @($lines | Where-Object { $_ -match 'bink2\.ds_boot_attract_injected' })
    $naturalGuest = @($lines | Where-Object { $_ -match 'bink2\.natural_guest_movie_observed' })
    $naturalAttract = @($naturalGuest | Where-Object { $_ -match "file='attract_movie\.bk2'" })
    $naturalLoop = @($naturalGuest | Where-Object { $_ -match "file='logo_intro_loop\.bk2'" })
    $attractAttach = @($lines | Where-Object {
        ($_ -match 'Bink RAD bridge attached:' -or $_ -match 'Bink2 NIHAV bridge attached:') -and
        $_ -match 'attract_movie\.bk2'
    })
    $directStarted = @($lines | Where-Object { $_ -match 'bink2\.direct_boot_started' })
    $directCompleted = @($lines | Where-Object { $_ -match 'bink2\.direct_boot_completed' })
    $radAttached = @($lines | Where-Object { $_ -match 'Bink RAD bridge attached:' })
    $fallback = @($lines | Where-Object { $_ -match 'Bink2 NIHAV bridge attached:' -or $_ -match 'bink2\.nihav_ready' })
    $hardGateStarted = @($lines | Where-Object { $_ -match 'bink2\.rad_guest_hard_gate_started' })
    $hardGateStopped = @($lines | Where-Object { $_ -match 'bink2\.rad_guest_hard_gate_stopped' })
    $filteredAudioIo = @($lines | Where-Object {
        $_ -match '\[LOADER\]\[TRACE\]' -and
        $_ -match 'pr_demons_souls_intro'
    })
    $sidecar = @($lines | Where-Object { $_ -match 'bink2\.rad_attract_audio_sidecar' })
    $unhandled = @($lines | Where-Object { $_ -match 'Unhandled exception' })

    $naturalAttractIndex = -1
    $attractAttachIndex = -1
    $directCompletedIndex = -1
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($naturalAttractIndex -lt 0 -and
            $lines[$i] -match 'bink2\.natural_guest_movie_observed' -and
            $lines[$i] -match "file='attract_movie\.bk2'") {
            $naturalAttractIndex = $i
        }
        if ($directCompletedIndex -lt 0 -and $lines[$i] -match 'bink2\.direct_boot_completed') {
            $directCompletedIndex = $i
        }
        if ($attractAttachIndex -lt 0 -and
            ($lines[$i] -match 'Bink RAD bridge attached:' -or $lines[$i] -match 'Bink2 NIHAV bridge attached:') -and
            $lines[$i] -match 'attract_movie\.bk2') {
            $attractAttachIndex = $i
        }
    }
    $attractAfterHandoff =
        $attractAttachIndex -ge 0 -and
        $directCompletedIndex -ge 0 -and
        $directCompletedIndex -lt $attractAttachIndex
    $attractGuestOwned =
        $attractAttachIndex -lt 0 -or
        ($naturalAttractIndex -ge 0 -and $naturalAttractIndex -lt $attractAttachIndex) -or
        ($hostAttractInjection.Count -eq 0 -and $badAutoOrders.Count -eq 0 -and $attractAfterHandoff)

    $movieClockSource = if ($naturalAttractIndex -ge 0) {
        "guest-natural-movie-open"
    } elseif ($attractAfterHandoff) {
        "guest-post-direct-boot-handoff-open"
    } elseif ($attractAttachIndex -lt 0) {
        "guest-attract-not-observed-yet"
    } else {
        "invalid-host-or-unproven-attract"
    }
    $audioClockEvidence = if ($filteredAudioIo.Count -gt 0) {
        "guest-intro-asset-io-observed"
    } elseif ($sidecar.Count -gt 0) {
        "host-sidecar-fallback-only"
    } else {
        "not-observed"
    }

    $strictProof =
        $hostAttractInjection.Count -eq 0 -and
        $badAutoOrders.Count -eq 0 -and
        $fallback.Count -eq 0 -and
        $attractGuestOwned -and
        $unhandled.Count -eq 0 -and
        ($canonicalAutoOrders.Count -gt 0 -or $naturalGuest.Count -gt 0)

    $classification = if (-not $strictProof) {
        "guest-media-handoff-failed"
    } elseif ($naturalAttractIndex -ge 0 -and $attractAttachIndex -ge 0) {
        "guest-driven-attract-observed"
    } elseif ($naturalGuest.Count -gt 0 -and $directStarted.Count -eq 0) {
        "natural-guest-movie-path-won-auto-boot-grace"
    } else {
        "canonical-host-bootstrap-handoff-awaiting-natural-attract"
    }

    $summary = @(
        "SharpEmu V72.4.3.2.31.7.8 GUEST MEDIA HANDOFF RESULT",
        "=================================================",
        ("WALL_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $exitCode),
        "ACTIVE_BINK_MODE=rad",
        ("CLASSIFICATION=" + $classification),
        ("AUTO_BOOT_ORDER_MARKERS=" + $autoOrders.Count),
        ("CANONICAL_AUTO_BOOT_ORDERS=" + $canonicalAutoOrders.Count),
        ("AUTO_BOOT_ORDERS_CONTAINING_ATTRACT=" + $badAutoOrders.Count),
        ("HOST_ATTRACT_INJECTION_MARKERS=" + $hostAttractInjection.Count),
        ("DIRECT_BOOT_STARTED=" + $directStarted.Count),
        ("DIRECT_BOOT_COMPLETED=" + $directCompleted.Count),
        ("NATURAL_GUEST_MOVIE_OBSERVATIONS=" + $naturalGuest.Count),
        ("NATURAL_LOGO_INTRO_LOOP_OBSERVED=" + $naturalLoop.Count),
        ("NATURAL_ATTRACT_OBSERVED=" + $naturalAttract.Count),
        ("ATTRACT_ATTACHES=" + $attractAttach.Count),
        ("ATTRACT_ATTACH_PRECEDED_BY_NATURAL_REQUEST_OR_POST_HANDOFF=" + $attractGuestOwned),
        ("ATTRACT_ATTACH_AFTER_DIRECT_BOOT_HANDOFF=" + $attractAfterHandoff),
        ("RAD_ATTACHES=" + $radAttached.Count),
        ("NIHAV_FALLBACK_HITS=" + $fallback.Count),
        ("RAD_HARD_GATE_STARTED=" + $hardGateStarted.Count),
        ("RAD_HARD_GATE_STOPPED=" + $hardGateStopped.Count),
        ("GUEST_INTRO_AUDIO_IO_MARKERS=" + $filteredAudioIo.Count),
        ("HOST_ATTRACT_SIDECAR_MARKERS=" + $sidecar.Count),
        ("MOVIE_CLOCK_SOURCE=" + $movieClockSource),
        ("AUDIO_CLOCK_EVIDENCE=" + $audioClockEvidence),
        "AUDIO_SIDEcar_STATUS=compatibility-fallback-preserved-until-guest-audio-event-proven",
        "ATTRACT_AUDIO_ANCHOR_DELAY_MS=0",
        "RAD_GUEST_WORK_POLICY=V31.7.6 hard gate preserved",
        "RAD_RENDER_LOCATION=sharpemu-child-window",
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count),
        ("STRICT_GUEST_MEDIA_HANDOFF_PROOF=" + $strictProof)
    )
    [IO.File]::WriteAllLines((Join-Path $out "SUMMARY.txt"),[string[]]$summary,(New-Object Text.UTF8Encoding($true)))

    $relevant = @($lines | Where-Object {
        $_ -match 'bink2\.' -or
        $_ -match 'Bink RAD bridge' -or
        $_ -match 'Bink2 NIHAV bridge' -or
        $_ -match 'pr_demons_souls_intro' -or
        $_ -match 'HOST_MOVIE_DECODER_' -or
        $_ -match 'Unhandled exception'
    })
    [IO.File]::WriteAllLines((Join-Path $out "MEDIA_RELEVANT.log"),[string[]]$relevant,(New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllLines((Join-Path $out "GUEST_INTRO_AUDIO_IO.log"),[string[]]$filteredAudioIo,(New-Object Text.UTF8Encoding($true)))

    $zip = $out + ".zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal

    Write-Host ""
    Get-Content -LiteralPath (Join-Path $out "SUMMARY.txt")
    Write-Host ""
    Write-Host ("[V72.4.3.2.31.7.8] RESULT ZIP: " + $zip) -ForegroundColor Green

    if (-not $strictProof) {
        throw "[V72.4.3.2.31.7.8] GUEST MEDIA HANDOFF PROOF FAILED. Result ZIP preserved."
    }
    Write-Host "[V72.4.3.2.31.7.8] GUEST MEDIA HANDOFF PROOF PASSED." -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name,$previous[$name],[System.EnvironmentVariableTarget]::Process)
    }
}
