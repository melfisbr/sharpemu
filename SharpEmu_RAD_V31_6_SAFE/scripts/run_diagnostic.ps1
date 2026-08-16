param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin")

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$exe = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"

foreach ($path in @($exe,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.6] Diagnostic prerequisite missing: $path"
    }
}

$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($rad)) {
    throw "[V72.4.3.2.31.6] RAD REQUIRED: radvideo64.exe not found."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $root ("SharpEmu_V72_4_3_2_31_6_RAD_ATTRACT_AUDIO_RESULT_" + $stamp)
$stdout = Join-Path $out "stdout.log"
$stderr = Join-Path $out "stderr.log"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$names = @(
    "SHARPEMU_BINK_MODE",
    "SHARPEMU_RADVIDEO64",
    "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
    "SHARPEMU_DS_INTRO_EXTERNAL_AUDIO",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS"
)
$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable(
        $name,
        [System.EnvironmentVariableTarget]::Process)
}

try {
    $env:SHARPEMU_BINK_MODE = "rad"
    $env:SHARPEMU_RADVIDEO64 = $rad
    $env:SHARPEMU_DS_ATTRACT_AUDIO_TEMPO = "1.0000"
    $env:SHARPEMU_DS_INTRO_EXTERNAL_AUDIO = "1"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS = "1500"

    Write-Host "[V72.4.3.2.31.6] RAD + attract external-stem audio test starting." -ForegroundColor Cyan
    Write-Host ("[V72.4.3.2.31.6] RAD=" + $rad)
    Write-Host "[V72.4.3.2.31.6] Policy: embedded Bink audio stays RAD-owned; attract_movie gets AT9 sidecar ONLY when its BK2 header reports tracks=0."
    Write-Host "[V72.4.3.2.31.6] Attract sidecar tempo=1.0000, offset=12.000 s."

    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.31.6] Unsupported quote in Eboot path."
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
        throw "[V72.4.3.2.31.6] Failed to start SharpEmu."
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

    $commands = @($lines | Where-Object { $_ -match 'bink2\.rad_command' })
    $started = @($lines | Where-Object { $_ -match 'bink2\.rad_required_started' })
    $attached = @($lines | Where-Object { $_ -match 'Bink RAD bridge attached:' })
    $completed = @($lines | Where-Object { $_ -match 'Bink RAD bridge completed:' })
    $completedOk = @($completed | Where-Object { $_ -match 'exit=0(?:\D|$)' })
    $completedBad = @($completed | Where-Object { $_ -match 'exit=(?!0(?:\D|$))\d+' })
    $fallback = @($lines | Where-Object {
        $_ -match 'Bink2 NIHAV bridge attached:' -or
        $_ -match 'bink2\.nihav_ready' -or
        $_ -match 'AttachFfmpeg'
    })
    $radErrors = @($lines | Where-Object {
        $_ -match 'bink2\.rad_(?:required_)?(?:missing|start_failed|attach_failed)' -or
        $_ -match 'bink2\.rad_player_(?:missing|start_failed)'
    })
    $headers = @($lines | Where-Object { $_ -match 'bink2\.rad_audio_header' })
    $attractZero = @($headers | Where-Object {
        $_ -match "file='attract_movie\.bk2'" -and $_ -match 'tracks=0(?:\D|$)'
    })
    $attractSidecar = @($lines | Where-Object {
        $_ -match 'bink2\.rad_attract_audio_sidecar'
    })
    $attractAudioStarts = @($lines | Where-Object {
        $_ -match 'bink2\.ds_intro_audio_start' -and $_ -match "file='attract_movie\.bk2'"
    })
    $attractUnavailable = @($lines | Where-Object {
        $_ -match 'bink2\.rad_attract_audio_unavailable' -or
        ($_ -match 'bink2\.ds_intro_audio_unavailable' -and $_ -match "attract_movie")
    })
    $unhandled = @($lines | Where-Object { $_ -match 'Unhandled exception' })

    $radHash = (Get-FileHash -LiteralPath $rad -Algorithm SHA256).Hash
    $strictProof =
        $commands.Count -ge 3 -and
        $started.Count -ge 3 -and
        $attached.Count -ge 3 -and
        $completedOk.Count -ge 2 -and
        $completedBad.Count -eq 0 -and
        $fallback.Count -eq 0 -and
        $radErrors.Count -eq 0 -and
        $attractZero.Count -ge 1 -and
        $attractSidecar.Count -ge 1 -and
        $attractAudioStarts.Count -ge 1 -and
        $attractUnavailable.Count -eq 0

    $summary = @(
        "SharpEmu V72.4.3.2.31.6 RAD ATTRACT AUDIO RESULT",
        "================================================",
        ("WALL_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $exitCode),
        "RAD_AVAILABLE=True",
        ("RAD_PLAYER=" + $rad),
        ("RAD_PLAYER_SHA256=" + $radHash),
        "ACTIVE_BINK_MODE=rad",
        ("RAD_COMMAND_MARKERS=" + $commands.Count),
        ("RAD_STARTED=" + $started.Count),
        ("RAD_ATTACHED=" + $attached.Count),
        ("RAD_COMPLETED_EXIT0=" + $completedOk.Count),
        ("RAD_COMPLETED_NONZERO=" + $completedBad.Count),
        ("RAD_AUDIO_HEADER_MARKERS=" + $headers.Count),
        ("ATTRACT_ZERO_EMBEDDED_TRACK_HEADER=" + ($attractZero.Count -ge 1)),
        ("ATTRACT_RAD_SIDECAR_MARKERS=" + $attractSidecar.Count),
        ("ATTRACT_AUDIO_STARTS=" + $attractAudioStarts.Count),
        ("ATTRACT_AUDIO_UNAVAILABLE=" + $attractUnavailable.Count),
        "ATTRACT_AUDIO_OFFSET_SECONDS=12.000",
        "ATTRACT_AUDIO_TEMPO=1.0000",
        ("NIHAV_OR_INTERNAL_FALLBACK_HITS=" + $fallback.Count),
        ("RAD_ERRORS=" + $radErrors.Count),
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count),
        ("STRICT_RAD_ATTRACT_AUDIO_PROOF=" + $strictProof),
        "RAD_RENDER_LOCATION=external-process-window"
    )

    [IO.File]::WriteAllLines(
        (Join-Path $out "SUMMARY.txt"),
        [string[]]$summary,
        (New-Object Text.UTF8Encoding($true)))

    $relevant = @($lines | Where-Object {
        $_ -match 'bink2\.' -or
        $_ -match 'Bink RAD bridge' -or
        $_ -match 'Bink2 NIHAV bridge' -or
        $_ -match 'Unhandled exception'
    })

    [IO.File]::WriteAllLines(
        (Join-Path $out "BINK_RELEVANT.log"),
        [string[]]$relevant,
        (New-Object Text.UTF8Encoding($true)))

    $zip = $out + ".zip"
    if (Test-Path -LiteralPath $zip) {
        Remove-Item -LiteralPath $zip -Force
    }
    Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal

    Write-Host ""
    Get-Content -LiteralPath (Join-Path $out "SUMMARY.txt")
    Write-Host ""
    Write-Host ("[V72.4.3.2.31.6] RESULT ZIP: " + $zip) -ForegroundColor Green

    if (-not $strictProof) {
        throw "[V72.4.3.2.31.6] STRICT RAD ATTRACT AUDIO PROOF FAILED. Result ZIP preserved."
    }

    Write-Host "[V72.4.3.2.31.6] STRICT RAD ATTRACT AUDIO PROOF PASSED." -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            [System.EnvironmentVariableTarget]::Process)
    }
}
