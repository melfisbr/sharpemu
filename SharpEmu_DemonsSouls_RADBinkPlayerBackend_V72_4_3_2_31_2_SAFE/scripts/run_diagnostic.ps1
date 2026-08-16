param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$exe =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"

foreach ($path in @($exe,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.2] Diagnostic prerequisite missing: $path"
    }
}

$rad = Find-RadVideo64 -RepositoryRoot $root
$radAvailable = -not [string]::IsNullOrWhiteSpace($rad)
$mode = if ($radAvailable) { "rad" } else { "native" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out =
    Join-Path $root (
        "SharpEmu_V72_4_3_2_31_2_RAD_OPTIONAL_BINK_RESULT_" +
        $stamp)
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
    $previous[$name] =
        [Environment]::GetEnvironmentVariable(
            $name,
            [System.EnvironmentVariableTarget]::Process)
}

try {
    $env:SHARPEMU_BINK_MODE = $mode

    if ($radAvailable) {
        $env:SHARPEMU_RADVIDEO64 = $rad
        $env:SHARPEMU_DS_ATTRACT_AUDIO_TEMPO = "1.0000"
    }
    else {
        Remove-Item Env:SHARPEMU_RADVIDEO64 -ErrorAction SilentlyContinue
        # Do not override DS attract tempo: preserve the installed V30 fallback baseline.
        Remove-Item Env:SHARPEMU_DS_ATTRACT_AUDIO_TEMPO -ErrorAction SilentlyContinue
    }

    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS = "1500"

    if ($radAvailable) {
        Write-Host "[V72.4.3.2.31.2] Starting Demon's Souls with RAD primary + NIHAV fallback."
        Write-Host ("[V72.4.3.2.31.2] RAD: " + $rad)
    }
    else {
        Write-Host "[V72.4.3.2.31.2] RAD not installed; testing native -> NIHAV -> FFmpeg fallback." -ForegroundColor Yellow
    }

    Write-Host "[V72.4.3.2.31.2] Expected startup chain: ps_studios_logo -> logo_intro -> attract_movie."
    Write-Host "[V72.4.3.2.31.2] Close SharpEmu normally after the test."

    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.31.2] Unsupported quote in Eboot path."
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
        throw "[V72.4.3.2.31.2] Failed to start SharpEmu."
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $proc.WaitForExit()
    $watch.Stop()

    $outText = $outTask.Result
    $errText = $errTask.Result
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    [IO.File]::WriteAllText(
        $stdout,$outText,(New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText(
        $stderr,$errText,(New-Object Text.UTF8Encoding($true)))

    $lines = @()
    $lines += ($errText -split "`r?`n")
    $lines += ($outText -split "`r?`n")

    $started =
        @($lines | Where-Object {
            $_ -match 'bink2\.rad_player_started'
        })
    $attached =
        @($lines | Where-Object {
            $_ -match 'Bink RAD bridge attached:'
        })
    $completed =
        @($lines | Where-Object {
            $_ -match 'Bink RAD bridge completed:'
        })
    $fallback =
        @($lines | Where-Object {
            $_ -match 'Bink2 NIHAV bridge attached:'
        })
    $radErrors =
        @($lines | Where-Object {
            $_ -match 'bink2\.rad_player_(missing|start_failed)'
        })
    $audioStarts =
        @($lines | Where-Object {
            $_ -match 'bink2\.ds_intro_audio_start'
        })
    $unhandled =
        @($lines | Where-Object {
            $_ -match 'Unhandled exception'
        })

    $radHash = "<none>"
    if ($radAvailable) {
        $radHash = (Get-FileHash -LiteralPath $rad -Algorithm SHA256).Hash
    }
    $radDisplay = if ($radAvailable) { $rad } else { "<not found>" }

    $summary = @(
        "SharpEmu V72.4.3.2.31.2 OPTIONAL RAD BINK RESULT",
        "===============================================",
        ("WALL_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $exitCode),
        ("RAD_AVAILABLE=" + $radAvailable),
        ("RAD_PLAYER=" + $radDisplay),
        ("RAD_PLAYER_SHA256=" + $radHash),
        ("ACTIVE_BINK_MODE=" + $mode),
        ("RAD_STARTED=" + $started.Count),
        ("RAD_ATTACHED=" + $attached.Count),
        ("RAD_COMPLETED=" + $completed.Count),
        ("NIHAV_FALLBACK_ATTACHES=" + $fallback.Count),
        ("RAD_ERRORS=" + $radErrors.Count),
        ("EXTERNAL_INTRO_AUDIO_STARTS=" + $audioStarts.Count),
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count)
    )

    [IO.File]::WriteAllLines(
        (Join-Path $out "SUMMARY.txt"),
        [string[]]$summary,
        (New-Object Text.UTF8Encoding($true)))

    $relevant =
        @($lines | Where-Object {
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

    Compress-Archive `
        -LiteralPath $out `
        -DestinationPath $zip `
        -CompressionLevel Optimal

    Write-Host ""
    Get-Content -LiteralPath (Join-Path $out "SUMMARY.txt")
    Write-Host ""
    Write-Host ("[V72.4.3.2.31.2] RESULT ZIP: " + $zip) -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            [System.EnvironmentVariableTarget]::Process)
    }
}
