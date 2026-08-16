param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root =
    (Resolve-Path -LiteralPath $RepositoryRoot).Path

$decoder =
    Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audio =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkHostAudioBridgeV7241.cs"
$bootstrap =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$tool =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$exe =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"

foreach ($path in @($decoder,$audio,$bootstrap,$tool,$exe,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.27] Diagnostic prerequisite missing: $path"
    }
}

$d = [IO.File]::ReadAllText($decoder)
$a = [IO.File]::ReadAllText($audio)
$b = [IO.File]::ReadAllText($bootstrap)

foreach ($marker in @(
    "V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP",
    "V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR",
    "V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX"
)) {
    if (-not $d.Contains($marker)) {
        throw "[V72.4.3.2.27] Decoder marker missing: $marker"
    }
}

if (-not $a.Contains(
        "V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO")) {
    throw "[V72.4.3.2.27] External intro audio hook missing."
}

if (-not $b.Contains(
        "V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES")) {
    throw "[V72.4.3.2.27] Buffered runtime defaults missing."
}

$toolHash =
    (Get-FileHash -LiteralPath $tool -Algorithm SHA256).
    Hash.ToLowerInvariant()

if ($toolHash -ne
    "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18") {
    throw (
        "[V72.4.3.2.27] Deployed NIHAV is not the benchmarked native build. " +
        "Current SHA256=" + $toolHash)
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out =
    Join-Path $root (
        "SharpEmu_V72_4_3_2_27_BINK_EXEC_COLOR_AUDIO_" +
        $stamp)
$truth = Join-Path $out "frame_truth"
$session = Join-Path $out "bink_session.log"
$stdout = Join-Path $out "stdout.log"
$stderr = Join-Path $out "stderr.log"

New-Item -ItemType Directory -Force -Path $truth | Out-Null

$names = @(
    "SHARPEMU_BINK_OUTPUT_MAX_WIDTH",
    "SHARPEMU_BINK_OUTPUT_MAX_HEIGHT",
    "SHARPEMU_NIHAV_SKIP_MODE",
    "SHARPEMU_BINK_FFMPEG_COLOR",
    "SHARPEMU_NIHAV_UV_SWAP",
    "SHARPEMU_BINK_PACKED_DIRECT",
    "SHARPEMU_BINK_FRAME_TRUTH_DIR",
    "SHARPEMU_BINK_SESSION_LOG",
    "SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION",
    "SHARPEMU_BINK_CHROMA_DEBLOCK",
    "SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD",
    "SHARPEMU_DS_INTRO_EXTERNAL_AUDIO",
    "SHARPEMU_LOG_BINK2",
    "SHARPEMU_BINK_HOST_CPU_LOGICAL",
    "SHARPEMU_NIHAV_FAST_PRIORITY",
    "SHARPEMU_BINK_REALTIME_DEADLINE",
    "SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES",
    "SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS",
    "SHARPEMU_BINK_HOST_TAIL_HOLD_MS",
    "SHARPEMU_BINK_MAX_CATCHUP_SKIP",
    "SHARPEMU_NIHAV_STREAM_FULL_CACHE"
)

$previous = @{}
foreach ($name in $names) {
    $previous[$name] =
        [Environment]::GetEnvironmentVariable($name)
}

try {
    $env:SHARPEMU_BINK_OUTPUT_MAX_WIDTH = "640"
    $env:SHARPEMU_BINK_OUTPUT_MAX_HEIGHT = "360"
    $env:SHARPEMU_NIHAV_SKIP_MODE = "none"
    $env:SHARPEMU_BINK_FFMPEG_COLOR = "0"
    $env:SHARPEMU_NIHAV_UV_SWAP = "0"
    $env:SHARPEMU_BINK_PACKED_DIRECT = "1"
    $env:SHARPEMU_BINK_FRAME_TRUTH_DIR = $truth
    $env:SHARPEMU_BINK_SESSION_LOG = $session
    $env:SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION = "1"
    $env:SHARPEMU_BINK_CHROMA_DEBLOCK = "1"
    $env:SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD = "24"
    $env:SHARPEMU_DS_INTRO_EXTERNAL_AUDIO = "1"
    $env:SHARPEMU_LOG_BINK2 = "1"
    $env:SHARPEMU_BINK_HOST_CPU_LOGICAL = "16"
    $env:SHARPEMU_NIHAV_FAST_PRIORITY = "2"
    $env:SHARPEMU_BINK_REALTIME_DEADLINE = "1"
    $env:SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES = "60"
    $env:SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS = "8"
    $env:SHARPEMU_BINK_HOST_TAIL_HOLD_MS = "13000"
    $env:SHARPEMU_BINK_MAX_CATCHUP_SKIP = "0"
    $env:SHARPEMU_NIHAV_STREAM_FULL_CACHE = "0"

    Write-Host "[V72.4.3.2.27] Starting Demon's Souls."
    Write-Host "[V72.4.3.2.27] NIHAV native + 60-frame buffer + U/V deblock + external intro audio."
    Write-Host "[V72.4.3.2.27] Close SharpEmu yourself after checking the boot videos/title. The script never force-stops it."

    $wall = [Diagnostics.Stopwatch]::StartNew()

    $process =
        Start-Process `
            -FilePath $exe `
            -ArgumentList @($Eboot) `
            -WorkingDirectory (Split-Path -Parent $exe) `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru

    $process.WaitForExit()
    $wall.Stop()

    $lines = New-Object Collections.Generic.List[string]

    foreach ($logPath in @($stderr,$stdout)) {
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            foreach ($line in Get-Content -LiteralPath $logPath) {
                $lines.Add([string]$line)
            }
        }
    }

    $completed = @(
        $lines |
        Where-Object {
            $_ -match 'Bink2 bridge completed:'
        }
    )

    $catchup = @(
        $lines |
        Where-Object {
            $_ -match 'bink2\.clock_catchup'
        }
    )

    $audioStarts = @(
        $lines |
        Where-Object {
            $_ -match 'bink2\.ds_intro_audio_start'
        }
    )

    $audioContinue = @(
        $lines |
        Where-Object {
            $_ -match 'bink2\.ds_intro_audio_continue'
        }
    )

    $audioErrors = @(
        $lines |
        Where-Object {
            $_ -match 'bink2\.ds_intro_audio_.*(failed|unavailable|missing)'
        }
    )

    $deadline = @(
        $lines |
        Where-Object {
            $_ -match 'bink2\.realtime_deadline'
        }
    )

    $perf = @(
        $lines |
        Where-Object {
            $_ -match 'bink2\.perf'
        }
    )

    $unhandled = @(
        $lines |
        Where-Object {
            $_ -match 'Unhandled exception'
        }
    )

    $summary = @(
        "SharpEmu V72.4.3.2.27 BINK EXECUTION COLOR AUDIO RESULT",
        "=========================================================",
        ("WALL_SECONDS=" + [Math]::Round($wall.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $process.ExitCode),
        ("NIHAV_SHA256=" + $toolHash),
        "OUTPUT=640x360",
        "PREFETCH_FRAMES=60",
        "PREFETCH_TIMEOUT_SECONDS=8",
        "MAX_CATCHUP_SKIP=0",
        "REFERENCE_COLOR_CALIBRATION=1",
        "CHROMA_DEBLOCK=1",
        "CHROMA_DEBLOCK_THRESHOLD=24",
        "EXTERNAL_INTRO_AUDIO=1",
        ("MOVIES_COMPLETED=" + $completed.Count),
        ("CLOCK_CATCHUP_EVENTS=" + $catchup.Count),
        ("INTRO_AUDIO_STARTS=" + $audioStarts.Count),
        ("INTRO_AUDIO_CONTINUES=" + $audioContinue.Count),
        ("INTRO_AUDIO_ERRORS=" + $audioErrors.Count),
        ("REALTIME_DEADLINES=" + $deadline.Count),
        ("PERF_SAMPLES=" + $perf.Count),
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count)
    )

    [IO.File]::WriteAllLines(
        (Join-Path $out "SUMMARY.txt"),
        [string[]]$summary,
        (New-Object Text.UTF8Encoding($true)))

    $relevant =
        @(
            $lines |
            Where-Object {
                $_ -match 'bink2\.' -or
                $_ -match 'Bink2 bridge' -or
                $_ -match 'Unhandled exception'
            }
        )

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
    Write-Host (
        "[V72.4.3.2.27] RESULT ZIP: " +
        $zip) `
        -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            EnvironmentVariableTarget.Process)
    }
}
