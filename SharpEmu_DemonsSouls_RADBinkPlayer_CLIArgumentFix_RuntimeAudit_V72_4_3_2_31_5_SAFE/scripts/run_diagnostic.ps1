param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin")

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$exe = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"

foreach ($path in @($exe,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.5] Diagnostic prerequisite missing: $path"
    }
}

$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($rad)) {
    throw "[V72.4.3.2.31.5] RAD REQUIRED: radvideo64.exe not found."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $root ("SharpEmu_V72_4_3_2_31_5_RAD_CLI_FIX_RESULT_" + $stamp)
$stdout = Join-Path $out "stdout.log"
$stderr = Join-Path $out "stderr.log"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$names = @(
    "SHARPEMU_BINK_MODE",
    "SHARPEMU_RADVIDEO64",
    "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
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
    Remove-Item Env:SHARPEMU_DS_ATTRACT_AUDIO_TEMPO -ErrorAction SilentlyContinue
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS = "1500"

    Write-Host "[V72.4.3.2.31.5] RAD CLI-FIX emulator test starting." -ForegroundColor Cyan
    Write-Host ("[V72.4.3.2.31.5] RAD=" + $rad)
    Write-Host "[V72.4.3.2.31.5] Expected RAD command marker: syntax='radvideo64.exe binkplay <movie>'"
    Write-Host "[V72.4.3.2.31.5] NOTE: V31.5 still launches BinkPlay as a separate process/window."
    Write-Host "[V72.4.3.2.31.5] RUN_6 audits whether an installed RAD runtime DLL/API is available for a true in-process backend."

    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.31.5] Unsupported quote in Eboot path."
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
        throw "[V72.4.3.2.31.5] Failed to start SharpEmu."
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
    $sidecarAudio = @($lines | Where-Object {
        $_ -match 'bink2\.ds_intro_audio_start' -or
        $_ -match 'bink2\.audio_start.*backend=presentation-sync'
    })
    $unhandled = @($lines | Where-Object { $_ -match 'Unhandled exception' })

    $radHash = (Get-FileHash -LiteralPath $rad -Algorithm SHA256).Hash
    $strictProof =
        $commands.Count -gt 0 -and
        $started.Count -gt 0 -and
        $attached.Count -gt 0 -and
        $completedOk.Count -gt 0 -and
        $completedBad.Count -eq 0 -and
        $fallback.Count -eq 0 -and
        $radErrors.Count -eq 0 -and
        $sidecarAudio.Count -eq 0

    $summary = @(
        "SharpEmu V72.4.3.2.31.5 RAD CLI ARGUMENT FIX RESULT",
        "====================================================",
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
        ("NIHAV_OR_INTERNAL_FALLBACK_HITS=" + $fallback.Count),
        ("RAD_ERRORS=" + $radErrors.Count),
        ("SHARPEMU_SIDECAR_AUDIO_STARTS=" + $sidecarAudio.Count),
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count),
        ("STRICT_RAD_CLI_PROOF=" + $strictProof),
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
    Write-Host ("[V72.4.3.2.31.5] RESULT ZIP: " + $zip) -ForegroundColor Green

    if (-not $strictProof) {
        throw "[V72.4.3.2.31.5] STRICT RAD CLI PROOF FAILED. Result ZIP preserved."
    }

    Write-Host "[V72.4.3.2.31.5] STRICT RAD CLI PROOF PASSED: at least one BinkPlay completed with exit=0 and no NIHAV/internal fallback was observed." -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            [System.EnvironmentVariableTarget]::Process)
    }
}
