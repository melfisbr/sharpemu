param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin")

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$exe = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
foreach ($path in @($exe,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.1] Diagnostic prerequisite missing: $path"
    }
}

$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($rad)) {
    throw "[V72.4.3.2.31.7.1] RAD REQUIRED: radvideo64.exe not found."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $root ("SharpEmu_V72_4_3_2_31_7_1_RAD_EMBEDDED_RESULT_" + $stamp)
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
    "SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS"
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
    $env:SHARPEMU_RAD_EMBED_TIMEOUT_MS = "10000"
    $env:SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS = "80"

    Write-Host "[V72.4.3.2.31.7.1] RAD embedded-host test starting." -ForegroundColor Cyan
    Write-Host ("[V72.4.3.2.31.7.1] RAD=" + $rad)
    Write-Host "[V72.4.3.2.31.7.1] External top-level RAD window is forbidden. BinkPlay must be reparented into SharpEmu."
    Write-Host "[V72.4.3.2.31.7.1] Attract audio anchor delay=80 ms after embedded playback readiness."

    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.31.7.1] Unsupported quote in Eboot path."
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
        throw "[V72.4.3.2.31.7.1] Failed to start SharpEmu."
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
    $started = @($lines | Where-Object { $_ -match 'bink2\.rad_required_started' })
    $hostAttached = @($lines | Where-Object { $_ -match 'bink2\.rad_host_attached' })
    $bridgeAttached = @($lines | Where-Object { $_ -match 'Bink RAD bridge attached:' })
    $hostReleased = @($lines | Where-Object { $_ -match 'bink2\.rad_host_released' })
    $hostFailures = @($lines | Where-Object {
        $_ -match 'bink2\.rad_host_(?:window_missing|setparent_failed|resize_failed)' -or
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

    $strictProof =
        $commands.Count -ge 3 -and
        $started.Count -ge 3 -and
        $hostAttached.Count -ge 3 -and
        $bridgeAttached.Count -ge 3 -and
        $hostFailures.Count -eq 0 -and
        $fallback.Count -eq 0 -and
        $attractSidecar.Count -ge 1 -and
        $attractAudioStarts.Count -ge 1 -and
        $audioAfterHost -and
        $unhandled.Count -eq 0

    $summary = @(
        "SharpEmu V72.4.3.2.31.7.1 RAD EMBEDDED HOST RESULT",
        "=================================================",
        ("WALL_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $exitCode),
        "ACTIVE_BINK_MODE=rad",
        ("RAD_COMMAND_I2=" + $commands.Count),
        ("RAD_STARTED=" + $started.Count),
        ("RAD_HOST_ATTACHED=" + $hostAttached.Count),
        ("RAD_BRIDGE_ATTACHED=" + $bridgeAttached.Count),
        ("RAD_HOST_RELEASED=" + $hostReleased.Count),
        ("RAD_EMBEDDED_HOST_FAILURES=" + $hostFailures.Count),
        ("NIHAV_FALLBACK_HITS=" + $fallback.Count),
        ("RAD_AUDIO_HEADER_MARKERS=" + $headers.Count),
        ("ATTRACT_RAD_SIDECAR_MARKERS=" + $attractSidecar.Count),
        ("ATTRACT_AUDIO_STARTS=" + $attractAudioStarts.Count),
        ("ATTRACT_AUDIO_ANCHOR_AFTER_HOST=" + $audioAfterHost),
        "ATTRACT_AUDIO_OFFSET_SECONDS=12.000",
        "ATTRACT_AUDIO_TEMPO=1.0000",
        "ATTRACT_AUDIO_ANCHOR_DELAY_MS=80",
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count),
        "RAD_RENDER_LOCATION=sharpemu-child-window",
        "TRUE_IN_PROCESS_BINK_SDK=False",
        ("STRICT_RAD_EMBEDDED_PROOF=" + $strictProof)
    )

    [IO.File]::WriteAllLines((Join-Path $out "SUMMARY.txt"),[string[]]$summary,(New-Object Text.UTF8Encoding($true)))

    $relevant = @($lines | Where-Object {
        $_ -match 'bink2\.' -or
        $_ -match 'Bink RAD bridge' -or
        $_ -match 'Bink2 NIHAV bridge' -or
        $_ -match 'Unhandled exception'
    })
    [IO.File]::WriteAllLines((Join-Path $out "BINK_RELEVANT.log"),[string[]]$relevant,(New-Object Text.UTF8Encoding($true)))

    $zip = $out + ".zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal

    Write-Host ""
    Get-Content -LiteralPath (Join-Path $out "SUMMARY.txt")
    Write-Host ""
    Write-Host ("[V72.4.3.2.31.7.1] RESULT ZIP: " + $zip) -ForegroundColor Green

    if (-not $strictProof) {
        throw "[V72.4.3.2.31.7.1] STRICT RAD EMBEDDED HOST PROOF FAILED. Result ZIP preserved."
    }

    Write-Host "[V72.4.3.2.31.7.1] STRICT RAD EMBEDDED HOST PROOF PASSED." -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name,$previous[$name],[System.EnvironmentVariableTarget]::Process)
    }
}
